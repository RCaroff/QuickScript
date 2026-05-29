import Cocoa

/// Lance un script dans une fenêtre Terminal.app (ou iTerm s'il est installé)
/// via AppleScript. L'app n'a pas accès aux logs runtime ni à l'exit code —
/// c'est le terminal qui prend le relais. Les valeurs de @param et les
/// variables d'environnement de contexte sont passées via la ligne de commande.
///
/// Le contenu de la session est néanmoins capturé dans un fichier .log via le
/// wrapper `script(1)` (utilitaire BSD).
enum TerminalLauncher {

    static func run(script: Script,
                    arguments: [String],
                    contextFiles: [String],
                    contextPath: String?) {
        let logURL = QSLog.newLogFileURL(for: script)
        let command = buildShellCommand(
            for: script,
            arguments: arguments,
            contextFiles: contextFiles,
            contextPath: contextPath,
            logFilePath: logURL.path
        )
        runInTerminal(command: command)
    }

    /// Construit une commande shell exportant les variables QS_* puis invoquant
    /// le script via le bon interpréteur, avec ses arguments correctement
    /// échappés. Si `logFilePath` est fourni, la commande est enveloppée avec
    /// `script(1)` pour capturer toute la session terminal dans le fichier.
    private static func buildShellCommand(for script: Script,
                                          arguments: [String],
                                          contextFiles: [String],
                                          contextPath: String?,
                                          logFilePath: String?) -> String {
        var parts: [String] = []

        if let p = contextPath {
            parts.append("export QS_CONTEXT_TARGET_PATH=\(shellEscape(p));")
        }
        if !contextFiles.isEmpty {
            let joined = contextFiles.joined(separator: "\n")
            parts.append("export QS_CONTEXT_FILE_PATH=\(shellEscape(joined));")
        }

        // Wrapper script(1) : -q (quiet, pas de header), -a (append).
        if let log = logFilePath {
            parts.append("script")
            parts.append("-q")
            parts.append("-a")
            parts.append(shellEscape(log))
        }

        let ext = (script.path as NSString).pathExtension.lowercased()
        if let interp = interpreter(for: ext) {
            parts.append("/usr/bin/env")
            parts.append(interp)
            parts.append(shellEscape(script.path))
        } else if FileManager.default.isExecutableFile(atPath: script.path) {
            parts.append(shellEscape(script.path))
        } else {
            parts.append("/bin/bash")
            parts.append(shellEscape(script.path))
        }
        for arg in arguments {
            parts.append(shellEscape(arg))
        }

        return parts.joined(separator: " ")
    }

    /// Échappement single-quote bash-safe : 'foo' → 'foo' ; foo'bar → 'foo'\''bar'.
    private static func shellEscape(_ s: String) -> String {
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Exécute la commande via AppleScript dans Terminal.app, ou iTerm si présent.
    private static func runInTerminal(command: String) {
        let iTermAvailable =
            FileManager.default.fileExists(atPath: "/Applications/iTerm.app") ||
            FileManager.default.fileExists(atPath: "\(NSHomeDirectory())/Applications/iTerm.app")
        let appName = iTermAvailable ? "iTerm" : "Terminal"

        // Échappement pour AppleScript : '\' puis '"'
        let asEscaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let source: String
        if iTermAvailable {
            source = """
            tell application "iTerm"
                activate
                set newWindow to (create window with default profile)
                tell current session of newWindow
                    write text "\(asEscaped)"
                end tell
            end tell
            """
        } else {
            source = """
            tell application "Terminal"
                activate
                do script "\(asEscaped)"
            end tell
            """
        }

        NSLog("QuickScript: AppleScript Terminal source:\n\(source)")

        guard let script = NSAppleScript(source: source) else {
            presentTerminalError(message: "Invalid AppleScript source.", appName: appName)
            return
        }

        var err: NSDictionary?
        script.executeAndReturnError(&err)

        if let err = err {
            NSLog("QuickScript: AppleScript Terminal error - \(err)")
            let message = (err["NSAppleScriptErrorMessage"] as? String) ?? "Unknown AppleScript error."
            let number = (err["NSAppleScriptErrorNumber"] as? Int) ?? 0
            presentTerminalError(message: "\(message) (code \(number))", appName: appName)
        }
    }

    private static func presentTerminalError(message: String, appName: String) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Unable to open \(appName)"
            alert.informativeText = """
            \(message)

            If the error is « \(appName) is not allowed assistance » or « not authorized », \
            check the permission in:

            System Settings → Privacy & Security → Automation → QuickScript → \(appName)

            The « \(appName) » checkbox must be enabled. If QuickScript does not appear at all, \
            run the script once more; macOS will prompt for permission on the first attempt.
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            _ = alert.runModal()
        }
    }

    private static func interpreter(for ext: String) -> String? {
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
