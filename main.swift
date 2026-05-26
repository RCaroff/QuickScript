import Cocoa
import Darwin
import UniformTypeIdentifiers

// ============================================================================
// MARK: - Modèle
// ============================================================================

struct Script: Codable {
    var id: UUID
    var name: String   // nom affiché dans le menu (renommable)
    var path: String   // chemin absolu vers le fichier

    init(id: UUID = UUID(), name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
    }

    // Codable synthétisé : les clés legacy (silent, openInTerminal, showLogs)
    // sont silencieusement ignorées et seront retirées au prochain save().
}

/// Paramètre déclaré dans l'en-tête d'un script via la directive `# @param`.
struct ScriptParam {
    let name: String
    let defaultValue: String?
    let description: String?
}

// ============================================================================
// MARK: - Persistance JSON
// ============================================================================

final class ScriptStore {
    static let shared = ScriptStore()

    /// Chemin du fichier JSON où la liste des scripts est persistée.
    let storageURL: URL
    private(set) var scripts: [Script] = []

    private init() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("QuickScript", isDirectory: true)
        if !fm.fileExists(atPath: folder.path) {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        self.storageURL = folder.appendingPathComponent("scripts.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        if let decoded = try? JSONDecoder().decode([Script].self, from: data) {
            scripts = decoded
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(scripts)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            NSLog("QuickScript: échec de sauvegarde - \(error)")
        }
    }

    func add(_ s: Script) { scripts.append(s); save() }
    func remove(id: UUID) { scripts.removeAll { $0.id == id }; save() }

    func update(_ s: Script) {
        if let idx = scripts.firstIndex(where: { $0.id == s.id }) {
            scripts[idx] = s
            save()
        }
    }

    func script(for id: UUID) -> Script? {
        return scripts.first(where: { $0.id == id })
    }
}

// ============================================================================
// MARK: - Parser de l'en-tête de script
// ============================================================================

enum ScriptHeaderParser {
    /// Extrait les paramètres déclarés en haut du script.
    ///
    /// Convention reconnue :
    ///
    ///   # @param NAME[=DEFAULT] [description libre]
    ///   #@param NAME            (sans espace après #, accepté)
    ///   // @param NAME          (pour des scripts en JS notamment)
    ///
    /// Le parser lit la tête du fichier et s'arrête à la première ligne non
    /// commentée / non vide / non shebang.
    static func parseParams(scriptPath: String) -> [ScriptParam] {
        guard
            let data = try? Data(contentsOf: URL(fileURLWithPath: scriptPath)),
            let content = String(data: data, encoding: .utf8)
        else { return [] }

        var params: [ScriptParam] = []
        let lines = content.components(separatedBy: .newlines).prefix(80)

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#!") { continue }            // shebang
            if line.hasPrefix("#") || line.hasPrefix("//") {
                if let param = parseParam(line: line) {
                    params.append(param)
                }
                continue
            }
            // Première ligne de code : on s'arrête.
            break
        }

        return params
    }

    private static func parseParam(line: String) -> ScriptParam? {
        // Supprime les marqueurs de commentaire de tête.
        var body = line
        for prefix in ["//", "#"] {
            if body.hasPrefix(prefix) {
                body = String(body.dropFirst(prefix.count))
                break
            }
        }
        body = body.trimmingCharacters(in: .whitespaces)

        // Doit commencer par @param
        guard body.lowercased().hasPrefix("@param") else { return nil }
        body = String(body.dropFirst("@param".count)).trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return nil }

        // Première "parole" = spec (NAME ou NAME=DEFAULT), reste = description
        let parts = body.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let spec = String(parts[0])
        let description = parts.count > 1
            ? String(parts[1]).trimmingCharacters(in: .whitespaces)
            : nil

        // Sépare NAME / DEFAULT
        if let eq = spec.firstIndex(of: "=") {
            let name = String(spec[..<eq])
            let def = String(spec[spec.index(after: eq)...])
            guard !name.isEmpty else { return nil }
            return ScriptParam(name: name, defaultValue: def, description: description)
        } else {
            return ScriptParam(name: spec, defaultValue: nil, description: description)
        }
    }
}

// ============================================================================
// MARK: - Dialog de saisie des paramètres
// ============================================================================

/// NSView avec coordonnées top-down (pratique pour empiler des champs).
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

enum ParamInputDialog {
    /// Affiche un dialog avec un text field par paramètre.
    /// Renvoie les valeurs si l'utilisateur valide, nil sinon.
    static func collect(params: [ScriptParam], scriptName: String) -> [String]? {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Paramètres pour « \(scriptName) »"
        alert.informativeText = "Renseigne les paramètres avant de lancer le script."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Lancer")
        alert.addButton(withTitle: "Annuler")

        let width: CGFloat = 380
        let labelHeight: CGFloat = 16
        let fieldHeight: CGFloat = 22
        let rowSpacing: CGFloat = 6
        let blockSpacing: CGFloat = 14
        let rowHeight = labelHeight + rowSpacing + fieldHeight + blockSpacing
        let totalHeight = CGFloat(params.count) * rowHeight - blockSpacing

        let container = FlippedView(
            frame: NSRect(x: 0, y: 0, width: width, height: max(totalHeight, fieldHeight))
        )

        var fields: [NSTextField] = []
        var y: CGFloat = 0

        for param in params {
            let labelText: String
            if let desc = param.description, !desc.isEmpty {
                labelText = "\(param.name) — \(desc)"
            } else {
                labelText = param.name
            }
            let label = NSTextField(labelWithString: labelText)
            label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
            label.frame = NSRect(x: 0, y: y, width: width, height: labelHeight)
            container.addSubview(label)

            let field = NSTextField(
                frame: NSRect(x: 0, y: y + labelHeight + rowSpacing, width: width, height: fieldHeight)
            )
            field.placeholderString = param.name
            if let def = param.defaultValue { field.stringValue = def }
            container.addSubview(field)
            fields.append(field)

            y += rowHeight
        }

        // Tab order = ordre des champs ajoutés
        for i in 0..<fields.count - 1 {
            fields[i].nextKeyView = fields[i + 1]
        }
        if fields.count > 1 {
            fields.last?.nextKeyView = fields.first
        }

        alert.accessoryView = container
        alert.window.initialFirstResponder = fields.first

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        return fields.map { $0.stringValue }
    }
}

// ============================================================================
// MARK: - Logs : fichier .log + fenêtre live
// ============================================================================

enum QSLog {
    /// Renvoie l'URL d'un nouveau fichier .log pour un lancement donné.
    /// Crée le sous-dossier par script à la volée.
    static func newLogFileURL(for script: Script) -> URL {
        let safe = sanitized(script.name)
        let dir = scriptLogDirectory(for: script)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd_HHmmss"
        let stamp = fmt.string(from: Date())
        return dir.appendingPathComponent("\(safe)-\(stamp).log")
    }

    /// Dossier dédié à un script, indépendamment d'un lancement particulier.
    static func scriptLogDirectory(for script: Script) -> URL {
        let dir = baseDirectory().appendingPathComponent(sanitized(script.name),
                                                         isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func baseDirectory() -> URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport
            .appendingPathComponent("QuickScript", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Remplace les caractères réservés du système de fichiers par `_`.
    private static func sanitized(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\")
        let parts = name.components(separatedBy: invalid)
        let joined = parts.joined(separator: "_")
        return joined.isEmpty ? "script" : joined
    }
}

/// Fenêtre persistante affichant les logs d'un script en temps réel.
/// Une instance par script, gérée par AppDelegate. La fenêtre persiste entre
/// les lancements (montrée/cachée à la demande via "Show/Hide logs window").
final class LogWindowController: NSWindowController, NSWindowDelegate, NSMenuDelegate {

    private let textView: NSTextView
    private let monoFont: NSFont
    private let revealButton: NSButton
    private let findButton: NSButton
    private let historyPopup: NSPopUpButton
    private let scriptLogsDirectory: URL

    /// URL du dernier lancement actif. Mis à jour à chaque attachToRun.
    private var logFileURL: URL?

    /// URL du fichier dont le contenu est actuellement affiché dans la textView.
    /// Distinct de `logFileURL` quand l'utilisateur visionne un log passé via
    /// le popup. Sert à conserver le bon item coché dans le menu.
    private var displayedURL: URL?

    /// Liste des fichiers .log présents dans `scriptLogsDirectory`, triés du
    /// plus récent au plus ancien. Aligné avec les items du popup.
    private var historyFiles: [URL] = []

    /// True = les chunks reçus via `append(_:)` sont ajoutés au texte affiché.
    /// False = le texte affiché est figé sur un fichier passé (loadFile).
    /// Reset à true à chaque `attachToRun(_:)`.
    private var liveMode: Bool = true

    /// Notifié quand la visibilité de la fenêtre change (show/hide/close).
    var onVisibilityChanged: (() -> Void)?

    // MARK: Date formatters

    /// Format du suffixe de nom de fichier : "yyyy-MM-dd_HHmmss".
    private static let filenameDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Format affiché dans le popup : "le 25/05/2026 à 14:30:45".
    private static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "'le' dd/MM/yyyy 'à' HH:mm:ss"
        f.locale = Locale(identifier: "fr_FR")
        return f
    }()

    /// Extrait la date depuis le nom de fichier (suffixe "yyyy-MM-dd_HHmmss").
    private static func parseDate(from url: URL) -> Date? {
        let name = url.deletingPathExtension().lastPathComponent
        guard name.count >= 17 else { return nil }
        let suffix = String(name.suffix(17))
        return filenameDateFormatter.date(from: suffix)
    }

    init(scriptName: String, scriptLogsDirectory: URL) {
        self.scriptLogsDirectory = scriptLogsDirectory
        self.logFileURL = nil

        let totalWidth: CGFloat = 720
        let totalHeight: CGFloat = 420
        let toolbarHeight: CGFloat = 40
        let separatorHeight: CGFloat = 1

        // Conteneur principal
        let contentView = NSView(frame: NSRect(x: 0, y: 0,
                                               width: totalWidth, height: totalHeight))
        contentView.autoresizingMask = [.width, .height]

        // Barre du haut + bouton "Afficher dans le Finder"
        let toolbar = NSView(frame: NSRect(x: 0, y: totalHeight - toolbarHeight,
                                           width: totalWidth, height: toolbarHeight))
        toolbar.autoresizingMask = [.width, .minYMargin]

        let reveal = NSButton(title: "Afficher dans le Finder",
                              target: nil,
                              action: #selector(revealLogInFinder))
        reveal.bezelStyle = .rounded
        reveal.image = NSImage(systemSymbolName: "folder",
                               accessibilityDescription: nil)
        reveal.imagePosition = .imageLeading
        reveal.sizeToFit()
        var bf = reveal.frame
        bf.origin.x = 12
        bf.origin.y = (toolbarHeight - bf.size.height) / 2
        reveal.frame = bf
        toolbar.addSubview(reveal)
        self.revealButton = reveal

        let find = NSButton(title: "Rechercher",
                            target: nil,
                            action: #selector(showFindBar))
        find.bezelStyle = .rounded
        find.image = NSImage(systemSymbolName: "magnifyingglass",
                             accessibilityDescription: nil)
        find.imagePosition = .imageLeading
        find.sizeToFit()
        var fbf = find.frame
        fbf.origin.x = reveal.frame.maxX + 8
        fbf.origin.y = (toolbarHeight - fbf.size.height) / 2
        find.frame = fbf
        toolbar.addSubview(find)
        self.findButton = find

        // Popup d'historique des logs, ancré à droite de la toolbar.
        let popupWidth: CGFloat = 240
        let popupHeight: CGFloat = 26
        let popup = NSPopUpButton(
            frame: NSRect(x: totalWidth - popupWidth - 12,
                          y: (toolbarHeight - popupHeight) / 2,
                          width: popupWidth,
                          height: popupHeight),
            pullsDown: false
        )
        popup.autoresizingMask = [.minXMargin]
        popup.target = nil
        popup.action = #selector(historySelected(_:))
        popup.toolTip = "Historique des lancements de ce script"
        toolbar.addSubview(popup)
        self.historyPopup = popup

        // Séparateur
        let sep = NSBox(frame: NSRect(x: 0,
                                      y: totalHeight - toolbarHeight - separatorHeight,
                                      width: totalWidth,
                                      height: separatorHeight))
        sep.boxType = .separator
        sep.autoresizingMask = [.width, .minYMargin]

        // ScrollView qui occupe le reste
        let scrollH = totalHeight - toolbarHeight - separatorHeight
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0,
                                                width: totalWidth, height: scrollH))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.autoresizingMask = [.width, .height]
        scroll.drawsBackground = false

        let font = NSFont.userFixedPitchFont(ofSize: 11) ?? NSFont.systemFont(ofSize: 11)
        self.monoFont = font

        let tv = NSTextView(frame: scroll.bounds)
        tv.isEditable = false
        tv.isSelectable = true
        tv.font = font
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.autoresizingMask = [.width]
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.backgroundColor = NSColor.textBackgroundColor
        // Active la find bar intégrée (Cmd+F, Cmd+G, Cmd+Shift+G).
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        self.textView = tv
        scroll.documentView = tv

        contentView.addSubview(scroll)
        contentView.addSubview(sep)
        contentView.addSubview(toolbar)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Logs — \(scriptName)"
        window.contentView = contentView
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self
        reveal.target = self
        find.target = self
        popup.target = self
        popup.menu?.delegate = self
        // Toujours actif : à défaut d'URL spécifique, on révèle le dossier
        // des logs du script.
        reveal.isEnabled = true

        // Première population du popup avec ce qui existe déjà sur disque.
        refreshHistory()
    }

    @objc private func showFindBar() {
        // S'assurer que le NSTextView est first responder pour que la find bar
        // de son NSScrollView s'affiche correctement.
        window?.makeFirstResponder(textView)
        let dummy = NSMenuItem()
        dummy.tag = NSTextFinder.Action.showFindInterface.rawValue
        textView.performTextFinderAction(dummy)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    /// Lie cette fenêtre au lancement courant. Met à jour l'URL exposée pour
    /// le bouton « Afficher dans le Finder », repasse en mode live, vide la
    /// vue (le runner va ré-écrire les chunks au fur et à mesure) et rafraîchit
    /// le popup d'historique avec la nouvelle entrée en tête.
    func attachToRun(logFileURL: URL) {
        self.logFileURL = logFileURL
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.liveMode = true
            self.displayedURL = logFileURL
            self.window?.representedURL = logFileURL
            self.textView.string = ""
            self.refreshHistory(highlighting: logFileURL)
        }
    }

    @objc private func revealLogInFinder() {
        // 1) le fichier .log du dernier lancement, si dispo
        if let url = logFileURL, FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        // 2) fallback : le dossier du script
        NSWorkspace.shared.activateFileViewerSelecting([scriptLogsDirectory])
    }

    /// Append du texte dans le NSTextView. Thread-safe. Ignoré si on est en
    /// mode "viewing" (un fichier passé est affiché via le popup).
    func append(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.liveMode,
                  let storage = self.textView.textStorage else { return }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: self.monoFont,
                .foregroundColor: NSColor.labelColor,
            ]
            storage.append(NSAttributedString(string: text, attributes: attrs))
            self.textView.scrollToEndOfDocument(nil)
        }
    }

    func appendInfoLine(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.liveMode,
                  let storage = self.textView.textStorage else { return }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: self.monoFont,
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            storage.append(NSAttributedString(string: text + "\n", attributes: attrs))
            self.textView.scrollToEndOfDocument(nil)
        }
    }

    // MARK: Historique des logs (popup)

    @objc private func historySelected(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        guard idx >= 0, idx < historyFiles.count else { return }
        loadFile(historyFiles[idx])
    }

    /// Charge un fichier .log dans le NSTextView. Si l'URL correspond au
    /// lancement courant (`self.logFileURL`), on repasse en mode live ;
    /// sinon, on est en "viewing mode" et les nouveaux chunks sont ignorés.
    private func loadFile(_ url: URL) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let storage = self.textView.textStorage else { return }

            let isCurrent = (url == self.logFileURL)

            let content: String
            if let data = try? Data(contentsOf: url),
               let s = String(data: data, encoding: .utf8) {
                content = s
            } else {
                content = "(impossible de lire le fichier)\n\(url.path)"
            }

            let attrs: [NSAttributedString.Key: Any] = [
                .font: self.monoFont,
                .foregroundColor: NSColor.labelColor,
            ]
            storage.setAttributedString(NSAttributedString(string: content, attributes: attrs))
            self.textView.scrollToEndOfDocument(nil)

            self.displayedURL = url
            // Bascule le mode live APRÈS avoir rempli la vue, pour que les
            // chunks éventuels en file d'attente sur main.async ne s'ajoutent
            // pas par dessus le snapshot qui les contient déjà.
            self.liveMode = isCurrent
        }
    }

    /// Rafraîchit la liste des fichiers .log du dossier du script et
    /// repopule le popup. Si `highlighting` est non nil et présent, le
    /// sélectionne.
    func refreshHistory(highlighting: URL? = nil) {
        let fm = FileManager.default
        var entries: [(URL, Date)] = []
        if let urls = try? fm.contentsOfDirectory(at: scriptLogsDirectory,
                                                  includingPropertiesForKeys: nil) {
            entries = urls
                .filter { $0.pathExtension == "log" }
                .compactMap { url -> (URL, Date)? in
                    guard let d = Self.parseDate(from: url) else { return nil }
                    return (url, d)
                }
        }
        // Inclut l'URL en cours même si le fichier n'a pas encore été créé
        // sur disque (attachToRun précède le createFile du runner).
        if let url = highlighting, !entries.contains(where: { $0.0 == url }),
           let d = Self.parseDate(from: url) {
            entries.append((url, d))
        }
        let sorted = entries.sorted { $0.1 > $1.1 }
        self.historyFiles = sorted.map { $0.0 }

        historyPopup.removeAllItems()
        if sorted.isEmpty {
            historyPopup.addItem(withTitle: "Aucun historique")
            historyPopup.isEnabled = false
        } else {
            historyPopup.isEnabled = true
            for (_, date) in sorted {
                historyPopup.addItem(withTitle: Self.displayDateFormatter.string(from: date))
            }
            if let url = highlighting,
               let idx = historyFiles.firstIndex(of: url) {
                historyPopup.selectItem(at: idx)
            }
        }
    }

    /// Rafraîchit le popup juste avant qu'il s'ouvre, pour montrer les fichiers
    /// récemment créés. Garde la coche sur le fichier actuellement affiché
    /// (pas forcément le run en cours, si l'utilisateur en a sélectionné un autre).
    func menuWillOpen(_ menu: NSMenu) {
        if menu === historyPopup.menu {
            refreshHistory(highlighting: displayedURL ?? logFileURL)
        }
    }

    /// État explicite (et non basé sur `window?.isVisible`, qui n'est pas
    /// encore false à l'instant de `windowWillClose`).
    private(set) var isShown: Bool = false

    func show() {
        isShown = true
        refreshHistory(highlighting: displayedURL ?? logFileURL)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        onVisibilityChanged?()
    }

    func hide() {
        isShown = false
        window?.orderOut(nil)
        onVisibilityChanged?()
    }

    func windowWillClose(_ notification: Notification) {
        // Fermeture via la croix native : on bascule l'état avant que le menu
        // soit reconstruit. isReleasedWhenClosed=false → contenu préservé.
        isShown = false
        onVisibilityChanged?()
    }
}

// ============================================================================
// MARK: - Runner (exécution silencieuse)
// ============================================================================

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
            showFailure(title: "Fichier introuvable",
                        info: "Le script n'existe plus à :\n\(script.path)")
            onFinish?()
            return
        }

        // Prépare le fichier .log (URL déjà calculée et partagée avec la fenêtre).
        FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        self.logFileHandle = try? FileHandle(forWritingTo: logFileURL)
        writeLogHeader()
        logWindow?.appendInfoLine("→ logs: \(logFileURL.path)\n")

        // Alloue un PTY (master côté app, slave côté script)
        guard let pty = PTY.open() else {
            showFailure(title: "PTY indisponible",
                        info: "Impossible d'allouer un pseudo-terminal pour ce script.")
            onFinish?()
            return
        }
        masterFD = pty.masterFD

        // Choix de l'interpréteur
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

        // Branche stdin / stdout / stderr du child sur l'extrémité slave du PTY.
        let slaveHandle = FileHandle(fileDescriptor: pty.slaveFD, closeOnDealloc: false)
        process.standardInput = slaveHandle
        process.standardOutput = slaveHandle
        process.standardError = slaveHandle

        // Environnement : TERM=dumb pour éviter les séquences ANSI de couleur.
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb"
        env["PYTHONUNBUFFERED"] = "1"
        if let path = contextPath {
            env["QS_CONTEXT_TARGET_PATH"] = path
        }
        if !contextFiles.isEmpty {
            // Un chemin par ligne. Pour un fichier unique, la variable contient
            // simplement son chemin. Pour plusieurs : itérer via
            // `while IFS= read -r f; do …; done <<< "$QS_CONTEXT_FILE_PATH"`.
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
            showFailure(title: "Échec du lancement",
                        info: error.localizedDescription)
            onFinish?()
            return
        }

        // Le child a son propre FD vers le slave (via dup2). Ferme le nôtre :
        // sans ça, le master ne recevra jamais d'EOF quand le child se termine.
        Darwin.close(pty.slaveFD)

        // Lecture asynchrone sur le master.
        let handle = FileHandle(fileDescriptor: pty.masterFD, closeOnDealloc: true)
        self.masterHandle = handle
        handle.readabilityHandler = { [weak self] h in
            let data = h.availableData
            if data.isEmpty { return }
            self?.onOutput(data)
        }

        // Timer de détection de prompt (main thread).
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

        // Persiste dans le fichier .log, suivi d'un saut de ligne entre chunks
        // (un chunk = un appel au readabilityHandler du PTY).
        if let handle = logFileHandle {
            do {
                try handle.write(contentsOf: data)
                try handle.write(contentsOf: Data("\n".utf8))
            } catch {
                NSLog("QuickScript: écriture log impossible - \(error)")
            }
        }

        // Affichage live, idem.
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
        // Main thread.
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
        alert.messageText = "« \(script.name) » attend une saisie"
        alert.informativeText = prompt
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Envoyer")
        alert.addButton(withTitle: "Annuler le script")

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
                    NSLog("QuickScript: écriture stdin impossible - \(error)")
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
            // Le terminationHandler s'occupe du nettoyage.
        }
    }

    // MARK: Fin d'exécution

    private func handleTermination() {
        guard !finished else { return }
        finished = true

        promptTimer?.invalidate()
        promptTimer = nil

        // Vide le master du PTY (lit jusqu'à EOF). EOF arrive parce qu'on a fermé
        // notre copie du slave après le run() et que le child est mort.
        if let handle = masterHandle {
            handle.readabilityHandler = nil
            // Lecture non bloquante des données restantes via availableData (en boucle).
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

        // Footer + close du fichier .log
        writeLogFooter(code: code)
        try? logFileHandle?.close()
        logFileHandle = nil

        // Message final dans la fenêtre live
        if code == 0 {
            logWindow?.appendInfoLine("\n→ terminé (exit 0)")
        } else if userCancelled {
            logWindow?.appendInfoLine("\n→ annulé par l'utilisateur")
        } else {
            logWindow?.appendInfoLine("\n→ erreur (exit \(code))")
        }

        defer { onFinish?() }

        if userCancelled {
            return
        }

        if code != 0 {
            showErrorAlert(code: code, logs: output)
        }
        // Succès → silencieux comme demandé.
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
        alert.messageText = "« \(script.name) » a échoué (code \(code))"
        alert.informativeText = "Le script s'est terminé avec une erreur. Détails ci-dessous."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Copier les logs")

        let cleaned = logs.trimmingCharacters(in: .whitespacesAndNewlines)
        let display = cleaned.isEmpty ? "(aucune sortie)" : cleaned
        alert.accessoryView = Self.makeScrollableText(display, width: 520, height: 240)

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(display, forType: .string)
        }
    }

    // MARK: Helpers

    private static func makeScrollableText(_ text: String, width: CGFloat, height: CGFloat) -> NSView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder

        let textView = NSTextView(frame: scroll.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.userFixedPitchFont(ofSize: 11) ?? NSFont.systemFont(ofSize: 11)
        textView.string = text
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false

        scroll.documentView = textView
        return scroll
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

// ============================================================================
// MARK: - TerminalLauncher (mode "ouvrir dans le terminal")
// ============================================================================

/// Lance un script dans une fenêtre Terminal.app (ou iTerm s'il est installé)
/// via AppleScript. L'app n'a pas accès aux logs ni à l'exit code — c'est le
/// terminal qui prend le relais. Les valeurs de @param et les variables
/// d'environnement de contexte sont passées via la ligne de commande.
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
        // Capture toute la session, y compris les prompts interactifs.
        if let log = logFilePath {
            parts.append("script")
            parts.append("-q")
            parts.append("-a")
            parts.append(shellEscape(log))
        }

        // Sélection de l'interpréteur, identique à ScriptRunner.
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
            presentTerminalError(message: "Source AppleScript invalide.", appName: appName)
            return
        }

        var err: NSDictionary?
        script.executeAndReturnError(&err)

        if let err = err {
            NSLog("QuickScript: erreur AppleScript Terminal - \(err)")
            let message = (err["NSAppleScriptErrorMessage"] as? String) ?? "Erreur AppleScript inconnue."
            let number = (err["NSAppleScriptErrorNumber"] as? Int) ?? 0
            presentTerminalError(message: "\(message) (code \(number))", appName: appName)
        }
    }

    private static func presentTerminalError(message: String, appName: String) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Impossible d'ouvrir \(appName)"
            alert.informativeText = """
            \(message)

            Si l'erreur est « \(appName) is not allowed assistance » ou « not authorized », \
            vérifie l'autorisation dans :

            Réglages Système → Confidentialité et sécurité → Automatisation → QuickScript → \(appName)

            La case « \(appName) » doit être cochée. Si QuickScript n'apparaît pas du tout, \
            relance le script une fois ; macOS proposera la permission au premier essai.
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

// ============================================================================
// MARK: - PTY (pseudo-terminal)
// ============================================================================

/// Alloue une paire master/slave de pseudo-terminal. Le slave est destiné à être
/// branché sur stdin/stdout/stderr du process enfant ; le master est lu/écrit
/// par l'app parente.
///
/// Le slave est configuré pour ne pas écho-er les saisies (sinon le contenu
/// envoyé via stdin serait re-vu dans l'output) et pour ne pas convertir les
/// `\n` en `\r\n`.
private enum PTY {
    static func open() -> (masterFD: Int32, slaveFD: Int32)? {
        let master = posix_openpt(O_RDWR | O_NOCTTY)
        guard master >= 0 else { return nil }

        guard grantpt(master) == 0,
              unlockpt(master) == 0,
              let nameC = ptsname(master) else {
            Darwin.close(master)
            return nil
        }
        let slaveName = String(cString: nameC)
        let slave = Darwin.open(slaveName, O_RDWR | O_NOCTTY)
        guard slave >= 0 else {
            Darwin.close(master)
            return nil
        }

        // Configuration du terminal slave
        var term = termios()
        if tcgetattr(slave, &term) == 0 {
            // Pas d'écho : ce qu'on écrit sur stdin du child ne réapparaît pas
            // dans l'output (sinon "Yann" taperait "Yann" en plus du résultat).
            term.c_lflag &= ~tcflag_t(ECHO)
            // Pas de conversion newline en sortie : on garde \n pur, plus facile
            // pour notre parseur de prompts.
            term.c_oflag &= ~tcflag_t(ONLCR)
            // Pas de conversion CR → LF en entrée.
            term.c_iflag &= ~tcflag_t(ICRNL)
            tcsetattr(slave, TCSANOW, &term)
        }

        return (master, slave)
    }
}

// ============================================================================
// MARK: - AppDelegate
// ============================================================================

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var runningRunners: Set<ObjectIdentifier> = []
    private var runnersByID: [ObjectIdentifier: ScriptRunner] = [:]
    private var logWindows: [UUID: LogWindowController] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()
        rebuildMenu()

        // Enregistre l'app comme fournisseur du Service déclaré dans Info.plist.
        // Permet l'apparition de « Exécuter avec QuickScript… » dans le menu
        // contextuel du Finder.
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    /// Installe un menu principal invisible (LSUIElement masque l'affichage)
    /// avec un menu Edit standard. Sans ça, Cmd+C/V/X/A ne sont pas routés vers
    /// les NSTextField des NSAlert (param dialog, prompt stdin, etc.).
    private func installEditMenu() {
        let main = NSMenu()

        // macOS exige un premier item App pour des raisons historiques, même
        // invisible. On le crée minimal.
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu(title: "QuickScript")
        main.addItem(appItem)

        // Menu Edit standard
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(NSMenuItem(title: "Undo",
                                action: Selector(("undo:")),
                                keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo",
                              action: Selector(("redo:")),
                              keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo)
        edit.addItem(NSMenuItem.separator())
        edit.addItem(NSMenuItem(title: "Cut",
                                action: #selector(NSText.cut(_:)),
                                keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "Copy",
                                action: #selector(NSText.copy(_:)),
                                keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Paste",
                                action: #selector(NSText.paste(_:)),
                                keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "Select All",
                                action: #selector(NSText.selectAll(_:)),
                                keyEquivalent: "a"))
        edit.addItem(NSMenuItem.separator())

        // Find — utilise le selector standard de NSTextView/NSTextFinder. Les
        // items ont `target = nil` → action routée via le responder chain
        // jusqu'au NSTextView focus (logs window).
        let findSel = #selector(NSTextView.performTextFinderAction(_:))
        let findItem = NSMenuItem(title: "Find…",
                                  action: findSel,
                                  keyEquivalent: "f")
        findItem.tag = NSTextFinder.Action.showFindInterface.rawValue
        edit.addItem(findItem)

        let findNext = NSMenuItem(title: "Find Next",
                                  action: findSel,
                                  keyEquivalent: "g")
        findNext.tag = NSTextFinder.Action.nextMatch.rawValue
        edit.addItem(findNext)

        let findPrev = NSMenuItem(title: "Find Previous",
                                  action: findSel,
                                  keyEquivalent: "G")
        findPrev.keyEquivalentModifierMask = [.command, .shift]
        findPrev.tag = NSTextFinder.Action.previousMatch.rawValue
        edit.addItem(findPrev)

        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    // MARK: Icône

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        if runningRunners.isEmpty {
            button.title = "⚡"
            button.toolTip = "QuickScript"
        } else {
            button.title = "⚡(\(runningRunners.count))"
            button.toolTip = "QuickScript — \(runningRunners.count) script(s) en cours"
        }
    }

    // MARK: Menu

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let scripts = ScriptStore.shared.scripts

        if scripts.isEmpty {
            let empty = NSMenuItem(title: "Aucun script importé", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for script in scripts {
                let item = NSMenuItem(
                    title: script.name,
                    action: #selector(runScript(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = script.id.uuidString
                item.toolTip = script.path

                let submenu = NSMenu()
                submenu.autoenablesItems = false

                let execute = NSMenuItem(title: "Exécuter",
                                         action: #selector(runScript(_:)),
                                         keyEquivalent: "")
                execute.target = self
                execute.representedObject = script.id.uuidString
                submenu.addItem(execute)

                // Variante affichée tant que la touche Option est maintenue :
                // exécute dans Terminal.app / iTerm au lieu du mode silencieux.
                let executeTerminal = NSMenuItem(title: "Exécuter dans le terminal",
                                                 action: #selector(runScriptInTerminal(_:)),
                                                 keyEquivalent: "")
                executeTerminal.target = self
                executeTerminal.representedObject = script.id.uuidString
                executeTerminal.isAlternate = true
                executeTerminal.keyEquivalentModifierMask = .option
                submenu.addItem(executeTerminal)

                let reveal = NSMenuItem(title: "Révéler dans le Finder",
                                        action: #selector(revealInFinder(_:)),
                                        keyEquivalent: "")
                reveal.target = self
                reveal.representedObject = script.id.uuidString
                submenu.addItem(reveal)

                submenu.addItem(NSMenuItem.separator())

                let isWindowShown = logWindows[script.id]?.isShown ?? false
                let logsToggle = NSMenuItem(
                    title: isWindowShown ? "Hide logs window" : "Show logs window",
                    action: #selector(toggleLogsWindow(_:)),
                    keyEquivalent: ""
                )
                logsToggle.target = self
                logsToggle.representedObject = script.id.uuidString
                logsToggle.toolTip =
                    "Affiche/cache la fenêtre des logs de ce script. " +
                    "Les chunks reçus pendant qu'elle est ouverte y sont affichés en direct. " +
                    "Indépendamment, un fichier .log est toujours créé à chaque lancement."
                submenu.addItem(logsToggle)

                submenu.addItem(NSMenuItem.separator())

                let rename = NSMenuItem(title: "Renommer…",
                                        action: #selector(renameScript(_:)),
                                        keyEquivalent: "")
                rename.target = self
                rename.representedObject = script.id.uuidString
                submenu.addItem(rename)

                let delete = NSMenuItem(title: "Supprimer",
                                        action: #selector(deleteScript(_:)),
                                        keyEquivalent: "")
                delete.target = self
                delete.representedObject = script.id.uuidString
                submenu.addItem(delete)

                item.submenu = submenu
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let addItem = NSMenuItem(title: "Ajouter un script…",
                                 action: #selector(addScript),
                                 keyEquivalent: "a")
        addItem.target = self
        menu.addItem(addItem)

        let openJSONItem = NSMenuItem(title: "Ouvrir scripts.json",
                                      action: #selector(openStorageJSON),
                                      keyEquivalent: "")
        openJSONItem.target = self
        openJSONItem.toolTip = ScriptStore.shared.storageURL.path
        menu.addItem(openJSONItem)

        // Variante affichée tant que la touche Option est maintenue.
        let revealJSONItem = NSMenuItem(title: "Afficher scripts.json",
                                        action: #selector(revealStorageJSON),
                                        keyEquivalent: "")
        revealJSONItem.target = self
        revealJSONItem.toolTip = "Révéler dans le Finder"
        revealJSONItem.isAlternate = true
        revealJSONItem.keyEquivalentModifierMask = .option
        menu.addItem(revealJSONItem)

        let refreshItem = NSMenuItem(title: "Actualiser",
                                     action: #selector(refreshFromDisk),
                                     keyEquivalent: "r")
        refreshItem.target = self
        refreshItem.toolTip = "Recharger scripts.json depuis le disque"
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quitter",
                                  action: #selector(quit),
                                  keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: Actions

    @objc private func addScript() {
        let panel = NSOpenPanel()
        panel.title = "Choisir un ou plusieurs scripts"
        panel.message = "Sélectionne un ou plusieurs fichiers .sh (Cmd+clic pour plusieurs)."
        panel.prompt = "Ajouter"
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.resolvesAliases = true

        // Restreint la sélection aux fichiers .sh
        if let shType = UTType(filenameExtension: "sh") {
            panel.allowedContentTypes = [shType]
        }

        NSApp.activate(ignoringOtherApps: true)

        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        for url in panel.urls {
            let defaultName = url.deletingPathExtension().lastPathComponent
            let script = Script(name: defaultName, path: url.path)
            ScriptStore.shared.add(script)
        }
        rebuildMenu()
    }

    @objc private func runScript(_ sender: NSMenuItem) {
        guard
            let idStr = sender.representedObject as? String,
            let id = UUID(uuidString: idStr),
            let script = ScriptStore.shared.script(for: id)
        else { return }
        launch(script: script)
    }

    /// Lance un script.
    /// - `contextFiles` (Quick Action sur sélection) : exposé via `$QS_CONTEXT_FILE_PATH`
    ///   (un chemin par ligne).
    /// - `contextPath` (Quick Action « ici ») : exposé via `$QS_CONTEXT_TARGET_PATH`.
    /// - `openInTerminal` : `true` → Terminal/iTerm prend le relais ; sinon PTY silencieux.
    private func launch(script: Script,
                        contextFiles: [String] = [],
                        contextPath: String? = nil,
                        openInTerminal: Bool = false) {
        if !FileManager.default.fileExists(atPath: script.path) {
            handleMissingScript(script)
            return
        }

        // Lire les @param du script
        let params = ScriptHeaderParser.parseParams(scriptPath: script.path)

        var args: [String] = []
        if !params.isEmpty {
            guard let values = ParamInputDialog.collect(params: params, scriptName: script.name) else {
                return // annulé par l'utilisateur
            }
            args = values
        }

        if openInTerminal {
            // Mode terminal : Terminal.app/iTerm prend le relais, on n'a aucun
            // contrôle (ni logs runtime, ni exit code, ni détection de prompt).
            // Le fichier .log est créé via le wrapper `script(1)`.
            TerminalLauncher.run(script: script,
                                 arguments: args,
                                 contextFiles: contextFiles,
                                 contextPath: contextPath)
            return
        }

        // Mode silencieux : PTY interne, capture, alertes. Si une fenêtre de
        // logs est ouverte (ou existe) pour ce script, on s'y attache : les
        // chunks reçus pendant l'exécution y seront affichés en direct.
        let logURL = QSLog.newLogFileURL(for: script)
        let attachedWindow = logWindows[script.id]
        attachedWindow?.attachToRun(logFileURL: logURL)

        let runner = ScriptRunner(script: script,
                                  arguments: args,
                                  contextFiles: contextFiles,
                                  contextPath: contextPath,
                                  logFileURL: logURL,
                                  logWindow: attachedWindow)
        let token = ObjectIdentifier(runner)
        runningRunners.insert(token)
        runnersByID[token] = runner
        updateStatusIcon()

        runner.run { [weak self] in
            DispatchQueue.main.async {
                self?.runningRunners.remove(token)
                self?.runnersByID.removeValue(forKey: token)
                self?.updateStatusIcon()
            }
        }
    }

    @objc private func renameScript(_ sender: NSMenuItem) {
        guard
            let idStr = sender.representedObject as? String,
            let id = UUID(uuidString: idStr),
            let script = ScriptStore.shared.script(for: id)
        else { return }

        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Renommer le script"
        alert.informativeText = "Choisis un nouveau nom d'affichage."
        alert.alertStyle = .informational

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        textField.stringValue = script.name
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField
        alert.addButton(withTitle: "Enregistrer")
        alert.addButton(withTitle: "Annuler")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { return }

        var updated = script
        updated.name = newName
        ScriptStore.shared.update(updated)
        rebuildMenu()
    }

    @objc private func runScriptInTerminal(_ sender: NSMenuItem) {
        guard
            let idStr = sender.representedObject as? String,
            let id = UUID(uuidString: idStr),
            let script = ScriptStore.shared.script(for: id)
        else { return }
        launch(script: script, openInTerminal: true)
    }

    @objc private func toggleLogsWindow(_ sender: NSMenuItem) {
        guard
            let idStr = sender.representedObject as? String,
            let id = UUID(uuidString: idStr),
            let script = ScriptStore.shared.script(for: id)
        else { return }

        let controller = ensureLogWindow(for: script)
        if controller.isShown {
            controller.hide()
        } else {
            controller.show()
        }
        // onVisibilityChanged appellera rebuildMenu() via le callback.
    }

    /// Renvoie le contrôleur de fenêtre de logs pour ce script, en le créant
    /// si nécessaire. Le callback de visibilité reconstruit le menu pour
    /// refléter l'état Show/Hide.
    private func ensureLogWindow(for script: Script) -> LogWindowController {
        if let existing = logWindows[script.id] {
            return existing
        }
        let dir = QSLog.scriptLogDirectory(for: script)
        let controller = LogWindowController(scriptName: script.name,
                                             scriptLogsDirectory: dir)
        controller.onVisibilityChanged = { [weak self] in
            self?.rebuildMenu()
        }
        logWindows[script.id] = controller
        return controller
    }

    @objc private func deleteScript(_ sender: NSMenuItem) {
        guard
            let idStr = sender.representedObject as? String,
            let id = UUID(uuidString: idStr),
            let script = ScriptStore.shared.script(for: id)
        else { return }

        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Supprimer ce script ?"
        alert.informativeText = "« \(script.name) » sera retiré de la liste. Le fichier d'origine ne sera pas supprimé."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Supprimer")
        alert.addButton(withTitle: "Annuler")

        if alert.runModal() == .alertFirstButtonReturn {
            // Nettoie la fenêtre de logs associée si elle existe.
            if let win = logWindows.removeValue(forKey: id) {
                win.window?.close()
            }
            ScriptStore.shared.remove(id: id)
            rebuildMenu()
        }
    }

    @objc private func revealInFinder(_ sender: NSMenuItem) {
        guard
            let idStr = sender.representedObject as? String,
            let id = UUID(uuidString: idStr),
            let script = ScriptStore.shared.script(for: id)
        else { return }

        if FileManager.default.fileExists(atPath: script.path) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: script.path)])
        } else {
            handleMissingScript(script)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func openStorageJSON() {
        let url = ScriptStore.shared.storageURL
        // Crée le fichier (vide ou avec la liste actuelle) s'il n'existe pas encore,
        // sinon NSWorkspace.open échouerait silencieusement.
        if !FileManager.default.fileExists(atPath: url.path) {
            ScriptStore.shared.save()
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func revealStorageJSON() {
        let url = ScriptStore.shared.storageURL
        if !FileManager.default.fileExists(atPath: url.path) {
            ScriptStore.shared.save()
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func refreshFromDisk() {
        ScriptStore.shared.load()
        rebuildMenu()
        updateStatusIcon()
    }

    // MARK: Script manquant

    private func handleMissingScript(_ script: Script) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Script introuvable"
        alert.informativeText =
            "Le fichier n'existe plus à l'emplacement :\n\n\(script.path)\n\nQue souhaites-tu faire ?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Choisir un nouveau chemin…")
        alert.addButton(withTitle: "Supprimer l'entrée")
        alert.addButton(withTitle: "Annuler")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            relocateScript(script)
        case .alertSecondButtonReturn:
            ScriptStore.shared.remove(id: script.id)
            rebuildMenu()
        default:
            break
        }
    }

    private func relocateScript(_ script: Script) {
        let panel = NSOpenPanel()
        panel.title = "Choisir le nouvel emplacement de « \(script.name) »"
        panel.prompt = "Mettre à jour"
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false

        NSApp.activate(ignoringOtherApps: true)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        var updated = script
        updated.path = url.path
        ScriptStore.shared.update(updated)
        rebuildMenu()
    }

    // MARK: Quick Action / NSService

    /// Handler invoqué quand l'utilisateur déclenche « Exécuter avec QuickScript… »
    /// sur une sélection de fichiers dans le Finder.
    @objc func runWithQuickScript(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let files = filePaths(from: pasteboard)
        guard !files.isEmpty else {
            error.pointee = "Aucun fichier sélectionné." as NSString
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.showScriptPicker(forFiles: files, contextPath: nil)
        }
    }

    /// Handler invoqué quand l'utilisateur déclenche « Exécuter avec QuickScript ici… »
    /// (clic droit dans le vide d'une fenêtre du Finder ou sur le Bureau).
    /// On interroge le Finder via AppleScript pour récupérer le dossier visible.
    @objc func runWithQuickScriptInContext(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let target = currentFinderInsertionPath() ?? NSHomeDirectory()
        DispatchQueue.main.async { [weak self] in
            self?.showScriptPicker(forFiles: [], contextPath: target)
        }
    }

    /// Demande au Finder le `insertion location` — le dossier dans lequel une
    /// opération « Nouveau dossier » serait effectuée. Sur le Bureau ou dans
    /// une fenêtre Finder, c'est ce qu'on veut. Nécessite la permission
    /// d'automation pour Finder (macOS la demande au premier appel).
    private func currentFinderInsertionPath() -> String? {
        let source = """
        tell application "Finder"
            try
                set theFolder to (insertion location as alias)
                return POSIX path of theFolder
            on error
                return ""
            end try
        end tell
        """

        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error = error {
            NSLog("QuickScript: AppleScript Finder error - \(error)")
            return nil
        }
        let path = result.stringValue ?? ""
        return path.isEmpty ? nil : path
    }

    /// Extrait les chemins de fichier du pasteboard (formats moderne + legacy).
    private func filePaths(from pasteboard: NSPasteboard) -> [String] {
        var paths: [String] = []

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            paths = urls.map { $0.path }
        }

        if paths.isEmpty {
            let legacy = NSPasteboard.PasteboardType("NSFilenamesPboardType")
            if let names = pasteboard.propertyList(forType: legacy) as? [String] {
                paths = names
            }
        }

        return paths
    }

    /// Affiche un picker pour choisir quel script lancer.
    /// - `files` : fichiers sélectionnés (exposés via $QS_CONTEXT_FILE_PATH).
    /// - `contextPath` : dossier courant du Finder (exposé via $QS_CONTEXT_TARGET_PATH).
    private func showScriptPicker(forFiles files: [String], contextPath: String?) {
        NSApp.activate(ignoringOtherApps: true)

        let scripts = ScriptStore.shared.scripts

        if scripts.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Aucun script à exécuter"
            alert.informativeText = "Ajoute d'abord un script via la barre des menus (« Ajouter un script… »)."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            _ = alert.runModal()
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Lancer")
        alert.addButton(withTitle: "Annuler")

        if let context = contextPath {
            alert.messageText = "Exécuter un script ici"
            alert.informativeText =
                "Le script aura accès au dossier via $QS_CONTEXT_TARGET_PATH :\n\n\(context)"
        } else {
            alert.messageText = "Exécuter un script"
            let fileLabel = files.count == 1
                ? "le fichier sélectionné"
                : "les \(files.count) fichiers sélectionnés"
            var detail = "Le script aura accès à \(fileLabel) via $QS_CONTEXT_FILE_PATH."
            if files.count <= 4 {
                detail += "\n\n" + files.map { "• \(($0 as NSString).lastPathComponent)" }.joined(separator: "\n")
            }
            alert.informativeText = detail
        }

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 26),
                                  pullsDown: false)
        for s in scripts {
            popup.addItem(withTitle: s.name)
        }
        alert.accessoryView = popup

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let idx = popup.indexOfSelectedItem
        guard idx >= 0 && idx < scripts.count else { return }
        launch(script: scripts[idx], contextFiles: files, contextPath: contextPath)
    }
}

// ============================================================================
// MARK: - Entrée
// ============================================================================

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // pas d'icône dans le Dock
app.run()
