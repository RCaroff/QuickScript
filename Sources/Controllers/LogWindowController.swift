import Cocoa

/// Fenêtre persistante affichant les logs d'un script en temps réel.
/// Une instance par script, gérée par AppDelegate. La fenêtre persiste entre
/// les lancements (montrée/cachée à la demande via "Show/Hide logs window").
///
/// Le NSTextView est connecté au runner via `attachToRun(_:)` puis `append(_:)`.
/// Un popup d'historique laisse l'utilisateur consulter d'anciens .log via
/// `loadFile(_:)`. Les codes ANSI sont interprétés via `ANSIParser`.
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

    /// Format displayed in the popup: "2026-05-25 14:30:45".
    private static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
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

        // Toolbar gérée en Auto Layout via NSStackView : les boutons gardent
        // leur taille intrinsèque, un spacer remplit l'espace libre, et le
        // popup d'historique se contracte si la fenêtre est trop étroite.
        let toolbar = NSView(frame: NSRect(x: 0, y: totalHeight - toolbarHeight,
                                           width: totalWidth, height: toolbarHeight))
        toolbar.autoresizingMask = [.width, .minYMargin]

        let reveal = NSButton(title: "Reveal in Finder",
                              target: nil,
                              action: #selector(revealLogInFinder))
        reveal.bezelStyle = .rounded
        reveal.image = NSImage(systemSymbolName: "folder",
                               accessibilityDescription: nil)
        reveal.imagePosition = .imageLeading
        reveal.translatesAutoresizingMaskIntoConstraints = false
        reveal.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        reveal.setContentCompressionResistancePriority(.required, for: .horizontal)
        self.revealButton = reveal

        let find = NSButton(title: "Find",
                            target: nil,
                            action: #selector(showFindBar))
        find.bezelStyle = .rounded
        find.image = NSImage(systemSymbolName: "magnifyingglass",
                             accessibilityDescription: nil)
        find.imagePosition = .imageLeading
        find.translatesAutoresizingMaskIntoConstraints = false
        find.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        find.setContentCompressionResistancePriority(.required, for: .horizontal)
        self.findButton = find

        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.target = nil
        popup.action = #selector(historySelected(_:))
        popup.toolTip = "Execution history for this script"
        popup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        popup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        self.historyPopup = popup

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [reveal, find, spacer, popup])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor),
            stack.topAnchor.constraint(equalTo: toolbar.topAnchor),
            stack.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor),
            popup.widthAnchor.constraint(lessThanOrEqualToConstant: 260),
            popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 110),
        ])

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
        reveal.isEnabled = true

        refreshHistory()
    }

    @objc private func showFindBar() {
        window?.makeFirstResponder(textView)
        let dummy = NSMenuItem()
        dummy.tag = NSTextFinder.Action.showFindInterface.rawValue
        textView.performTextFinderAction(dummy)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    /// Lie cette fenêtre au lancement courant. Met à jour l'URL exposée pour
    /// le bouton « Reveal in Finder », repasse en mode live, vide la
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
        let target = displayedURL ?? logFileURL
        if let url = target, FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([scriptLogsDirectory])
    }

    /// Append du texte dans le NSTextView. Thread-safe. Ignoré si on est en
    /// mode "viewing" (un fichier passé est affiché via le popup).
    /// Les séquences ANSI escape codes éventuelles sont interprétées en
    /// couleurs / bold / italic / underline.
    func append(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.liveMode,
                  let storage = self.textView.textStorage else { return }
            let attributed = ANSIParser.attributedString(from: text, baseFont: self.monoFont)
            storage.append(attributed)
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
                content = "(unable to read file)\n\(url.path)"
            }

            let attributed = ANSIParser.attributedString(from: content, baseFont: self.monoFont)
            storage.setAttributedString(attributed)
            self.textView.scrollToEndOfDocument(nil)

            self.displayedURL = url
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
        if let url = highlighting, !entries.contains(where: { $0.0 == url }),
           let d = Self.parseDate(from: url) {
            entries.append((url, d))
        }
        let sorted = entries.sorted { $0.1 > $1.1 }
        self.historyFiles = sorted.map { $0.0 }

        historyPopup.removeAllItems()
        if sorted.isEmpty {
            historyPopup.addItem(withTitle: "No history")
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

        if displayedURL == nil, let mostRecent = historyFiles.first {
            loadFile(mostRecent)
        }

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
        isShown = false
        onVisibilityChanged?()
    }
}
