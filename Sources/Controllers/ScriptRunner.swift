import Cocoa
import Darwin

/// Exécute un script silencieusement via un pseudo-terminal (PTY).
///
/// - stdout + stderr fusionnés sont capturés sur le master du PTY
/// - Écrit dans le fichier .log (avec saut de ligne entre chunks)
/// - Stream live vers une `LogWindowController` si fournie
/// - Détecte les prompts stdin (heuristique) et propose un dialog
/// - À la fin : alerte d'erreur si exit code ≠ 0
final class ScriptRunner {

    private let script: Script
    private let arguments: [String]
    private let contextFiles: [String]
    private let contextPath: String?
    private let logWindow: LogWindowController?
    private let logFileURL: URL
    private var logFileHandle: FileHandle?

    private let process = Process()

    // PTY : un seul "pipe bidirectionnel" qui se comporte comme un vrai terminal
    // côté child → bash, python, etc. affichent leurs prompts correctement, et
    // stdout+stderr arrivent fusionnés sur le master côté parent.
    private var masterFD: Int32 = -1
    private var masterHandle: FileHandle?

    private let queue = DispatchQueue(label: "QuickScript.runner.\(UUID().uuidString)")

    // État partagé entre la queue background et le main thread.
    private var outputData = Data()      // tout l'output (PTY = stdout + stderr fusionnés)
    private var pendingPrompt = Data()   // contenu depuis le dernier '\n'
    private var lastOutputAt = Date()
    private var promptTimer: Timer?
    private var promptShown = false
    private var userCancelled = false
    private var finished = false

    private var onFinish: (() -> Void)?

    init(script: Script,
         arguments: [String] = [],
         contextFiles: [String] = [],
         contextPath: String? = nil,
         logFileURL: URL,
         logWindow: LogWindowController? = nil) {
        self.script = script
        self.arguments = arguments
        self.contextFiles = contextFiles
        self.contextPath = contextPath
        self.logFileURL = logFileURL
        self.logWindow = logWindow
    }

    // MARK: Lancement

    func run(onFinish: (() -> Void)? = nil) {
        self.onFinish = onFinish

        guard FileManager.default.fileExists(atPath: script.path) else {
            showFailure(title: "File not found",
                        info: "The script no longer exists at:\n\(script.path)")
            onFinish?()
            return
        }

        FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        self.logFileHandle = try? FileHandle(forWritingTo: logFileURL)
        writeLogHeader()
        logWindow?.appendInfoLine("→ logs: \(logFileURL.path)\n")

        guard let pty = PTY.open() else {
            showFailure(title: "PTY unavailable",
                        info: "Unable to allocate a pseudo-terminal for this script.")
            onFinish?()
            return
        }
        masterFD = pty.masterFD

        let ext = (script.path as NSString).pathExtension.lowercased()
        let interp = Self.interpreter(for: ext)

        if let interp = interp {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [interp, script.path] + arguments
        } else if FileManager.default.isExecutableFile(atPath: script.path) {
            process.executableURL = URL(fileURLWithPath: script.path)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [script.path] + arguments
        }

        let slaveHandle = FileHandle(fileDescriptor: pty.slaveFD, closeOnDealloc: false)
        process.standardInput = slaveHandle
        process.standardOutput = slaveHandle
        process.standardError = slaveHandle

        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb"
        env["PYTHONUNBUFFERED"] = "1"
        if let path = contextPath {
            env["QS_CONTEXT_TARGET_PATH"] = path
        }
        if !contextFiles.isEmpty {
            env["QS_CONTEXT_FILE_PATH"] = contextFiles.joined(separator: "\n")
        }
        process.environment = env

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.handleTermination() }
        }

        do {
            try process.run()
        } catch {
            Darwin.close(pty.masterFD)
            Darwin.close(pty.slaveFD)
            masterFD = -1
            showFailure(title: "Launch failed",
                        info: error.localizedDescription)
            onFinish?()
            return
        }

        // Ferme notre copie du slave pour que le master reçoive EOF à la fin du child.
        Darwin.close(pty.slaveFD)

        let handle = FileHandle(fileDescriptor: pty.masterFD, closeOnDealloc: true)
        self.masterHandle = handle
        handle.readabilityHandler = { [weak self] h in
            let data = h.availableData
            if data.isEmpty { return }
            self?.onOutput(data)
        }

        promptTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.checkForPrompt()
        }
    }

    // MARK: Lecture du PTY

    private func onOutput(_ data: Data) {
        queue.sync {
            outputData.append(data)
            appendToPendingPromptLocked(data)
        }

        // Persiste dans le fichier .log, suivi d'un saut de ligne entre chunks.
        if let handle = logFileHandle {
            do {
                try handle.write(contentsOf: data)
                try handle.write(contentsOf: Data("\n".utf8))
            } catch {
                NSLog("QuickScript: unable to write log - \(error)")
            }
        }

        if let window = logWindow, let s = String(data: data, encoding: .utf8) {
            window.append(s + "\n")
        }
    }

    private func writeLogHeader() {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let stamp = fmt.string(from: Date())
        var header = "=== QuickScript log ===\n"
        header += "Script : \(script.name) (\(script.path))\n"
        header += "Started: \(stamp)\n"
        if !arguments.isEmpty {
            header += "Args   : \(arguments.joined(separator: " "))\n"
        }
        if let ctx = contextPath {
            header += "QS_CONTEXT_TARGET_PATH=\(ctx)\n"
        }
        if !contextFiles.isEmpty {
            header += "QS_CONTEXT_FILE_PATH:\n"
            for f in contextFiles { header += "  \(f)\n" }
        }
        header += "------------------------\n"
        if let data = header.data(using: .utf8) {
            try? logFileHandle?.write(contentsOf: data)
        }
    }

    private func writeLogFooter(code: Int32) {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let stamp = fmt.string(from: Date())
        let footer = "\n------------------------\nExit \(code) at \(stamp)\n"
        if let data = footer.data(using: .utf8) {
            try? logFileHandle?.write(contentsOf: data)
        }
    }

    /// Doit être appelé depuis `queue`. Ajoute `data` au buffer de prompt et le tronque
    /// pour ne conserver que ce qui suit le dernier '\n'.
    private func appendToPendingPromptLocked(_ data: Data) {
        pendingPrompt.append(data)
        if let s = String(data: pendingPrompt, encoding: .utf8),
           let lastNL = s.lastIndex(of: "\n") {
            let after = s[s.index(after: lastNL)...]
            pendingPrompt = Data(String(after).utf8)
        }
        lastOutputAt = Date()
    }

    // MARK: Détection de prompt

    private func checkForPrompt() {
        guard !promptShown, !finished, process.isRunning else { return }

        var bufferCopy = Data()
        var idle: TimeInterval = 0
        queue.sync {
            bufferCopy = pendingPrompt
            idle = Date().timeIntervalSince(lastOutputAt)
        }

        guard !bufferCopy.isEmpty else { return }
        guard let text = String(data: bufferCopy, encoding: .utf8) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Heuristique : ressemble à un prompt si se termine par : ? > ] ou si idle > 2.5s
        let endsLikePrompt = ":?>]".contains(trimmed.last!)
        let veryIdle = idle > 2.5
        let probablyPrompt = endsLikePrompt && idle > 0.35

        guard probablyPrompt || veryIdle else { return }

        promptShown = true
        showStdinPromptDialog(prompt: text)
    }

    private func showStdinPromptDialog(prompt: String) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "« \(script.name) » is waiting for input"
        alert.informativeText = prompt
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Send")
        alert.addButton(withTitle: "Cancel script")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 22))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            let answer = field.stringValue + "\n"
            if let data = answer.data(using: .utf8) {
                do {
                    try masterHandle?.write(contentsOf: data)
                } catch {
                    NSLog("QuickScript: unable to write stdin - \(error)")
                }
            }
            queue.sync {
                pendingPrompt.removeAll()
                lastOutputAt = Date()
            }
            promptShown = false
        } else {
            userCancelled = true
            promptShown = false
            if process.isRunning {
                process.terminate()
            }
        }
    }

    // MARK: Fin d'exécution

    private func handleTermination() {
        guard !finished else { return }
        finished = true

        promptTimer?.invalidate()
        promptTimer = nil

        if let handle = masterHandle {
            handle.readabilityHandler = nil
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                queue.sync { outputData.append(chunk) }
            }
        }
        masterHandle = nil
        masterFD = -1

        let code = process.terminationStatus
        let output = queue.sync { String(data: outputData, encoding: .utf8) ?? "" }

        writeLogFooter(code: code)
        try? logFileHandle?.close()
        logFileHandle = nil

        if code == 0 {
            logWindow?.appendInfoLine("\n→ done (exit 0)")
        } else if userCancelled {
            logWindow?.appendInfoLine("\n→ cancelled by user")
        } else {
            logWindow?.appendInfoLine("\n→ error (exit \(code))")
        }

        defer { onFinish?() }

        if userCancelled {
            return
        }

        if code != 0 {
            showErrorAlert(code: code, logs: output)
        }
    }

    // MARK: Affichages d'erreur

    private func showFailure(title: String, info: String) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = info
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            _ = alert.runModal()
        }
    }

    private func showErrorAlert(code: Int32, logs: String) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "« \(script.name) » failed (code \(code))"
        alert.informativeText = "The script ended with an error. Details below."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Copy logs")

        let cleaned = logs.trimmingCharacters(in: .whitespacesAndNewlines)
        let display = cleaned.isEmpty ? "(no output)" : cleaned
        let font = NSFont.userFixedPitchFont(ofSize: 11) ?? NSFont.systemFont(ofSize: 11)
        let attributedLogs = ANSIParser.attributedString(from: display, baseFont: font)
        alert.accessoryView = Self.makeScrollableText(attributedLogs, width: 520, height: 240)

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(attributedLogs.string, forType: .string)
        }
    }

    // MARK: Helpers

    private static func makeScrollableText(_ attributedText: NSAttributedString,
                                           width: CGFloat, height: CGFloat) -> NSView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder

        let textView = NSTextView(frame: scroll.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textStorage?.setAttributedString(attributedText)

        scroll.documentView = textView
        return scroll
    }

    static func interpreter(for ext: String) -> String? {
        switch ext {
        case "py":              return "python3"
        case "sh", "bash":      return "bash"
        case "zsh":             return "zsh"
        case "rb":              return "ruby"
        case "js", "mjs":       return "node"
        case "pl":              return "perl"
        case "php":             return "php"
        default:                return nil
        }
    }
}
