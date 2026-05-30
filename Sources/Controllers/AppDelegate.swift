import Cocoa
import UniformTypeIdentifiers

/// Coordinateur principal de l'app. Gère :
/// - le menu de la barre de statut (status item)
/// - le main menu invisible (raccourcis clavier Edit + Find)
/// - le cycle de vie des `ScriptRunner` actifs (badge dans la status bar)
/// - les `LogWindowController` (une par script, persistantes)
/// - les `ParamEditorWindowController` (fenêtres d'édition de @param)
/// - les handlers Quick Action / NSService (clic droit dans Finder)
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var runningRunners: Set<ObjectIdentifier> = []
    private var runnersByID: [ObjectIdentifier: ScriptRunner] = [:]
    private var logWindows: [UUID: LogWindowController] = [:]
    private var paramEditors: [ParamEditorWindowController] = []

    // Préférence globale : si true, la fenêtre de logs est forcée à s'ouvrir
    // à chaque lancement de script (peu importe son état précédent).
    private let alwaysShowLogsKey = "alwaysShowLogsAtRun"
    private var alwaysShowLogsAtRun: Bool {
        get { UserDefaults.standard.bool(forKey: alwaysShowLogsKey) }
        set { UserDefaults.standard.set(newValue, forKey: alwaysShowLogsKey) }
    }

    // Préférence globale : si true, tout clic sur « Run » est traité comme
    // « Run in terminal » (Terminal.app / iTerm prend le relais).
    private let alwaysRunInTerminalKey = "alwaysRunInTerminal"
    private var alwaysRunInTerminal: Bool {
        get { UserDefaults.standard.bool(forKey: alwaysRunInTerminalKey) }
        set { UserDefaults.standard.set(newValue, forKey: alwaysRunInTerminalKey) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()
        rebuildMenu()

        // Enregistre l'app comme fournisseur du Service déclaré dans Info.plist.
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    /// Installe un menu principal invisible (LSUIElement masque l'affichage)
    /// avec un menu Edit standard. Sans ça, Cmd+C/V/X/A ne sont pas routés vers
    /// les NSTextField des NSAlert (param dialog, prompt stdin, etc.).
    private func installEditMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        appItem.submenu = NSMenu(title: "QuickScript")
        main.addItem(appItem)

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

        // Find — routé via responder chain jusqu'au NSTextView focus.
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

    // MARK: Icône status bar

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }

        // Charge l'icône menu bar (template image) — macOS la recolore
        // automatiquement selon le thème clair/sombre. Taille des icônes
        // menu bar : 18 points de hauteur (convention macOS) ; la largeur
        // suit le ratio natif du PNG (2:1 → 36 points).
        if button.image == nil, let image = NSImage(named: "menu-icon") {
            image.isTemplate = true
            let aspect = image.size.width / max(image.size.height, 1)
            image.size = NSSize(width: 18 * aspect, height: 18)
            button.image = image
            button.imagePosition = .imageLeft
        }

        // Fallback texte si l'icône n'est pas chargée (dev / build sans Resources).
        if button.image == nil {
            button.title = runningRunners.isEmpty
                ? "⚡"
                : "⚡ (\(runningRunners.count))"
        } else {
            // Avec l'image chargée, le titre n'affiche que le badge de compteur.
            button.title = runningRunners.isEmpty
                ? ""
                : " (\(runningRunners.count))"
        }

        button.toolTip = runningRunners.isEmpty
            ? "QuickScript"
            : "QuickScript — \(runningRunners.count) running script(s)"
    }

    // MARK: Menu

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let scripts = ScriptStore.shared.scripts

        if scripts.isEmpty {
            let empty = NSMenuItem(title: "No scripts added", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for script in scripts {
                // Pas d'action sur l'item racine : un clic ouvre seulement le
                // sous-menu. L'exécution passe par « Run » ou son alternate
                // « Run in terminal » (Option).
                let item = NSMenuItem(
                    title: script.name,
                    action: nil,
                    keyEquivalent: ""
                )
                item.representedObject = script.id.uuidString

                let submenu = NSMenu()
                submenu.autoenablesItems = false

                let execute = NSMenuItem(title: "Run",
                                         action: #selector(runScript(_:)),
                                         keyEquivalent: "")
                execute.target = self
                execute.representedObject = script.id.uuidString
                submenu.addItem(execute)

                let executeTerminal = NSMenuItem(title: "Run in terminal",
                                                 action: #selector(runScriptInTerminal(_:)),
                                                 keyEquivalent: "")
                executeTerminal.target = self
                executeTerminal.representedObject = script.id.uuidString
                executeTerminal.isAlternate = true
                executeTerminal.keyEquivalentModifierMask = .option
                submenu.addItem(executeTerminal)

                let reveal = NSMenuItem(title: "Reveal in Finder",
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
                    "Show/hide the logs window for this script. " +
                    "Chunks received while it is open are displayed live. " +
                    "A .log file is always created at every launch, regardless."
                submenu.addItem(logsToggle)

                submenu.addItem(NSMenuItem.separator())

                let editParams = NSMenuItem(title: "Edit parameters…",
                                            action: #selector(editScriptParams(_:)),
                                            keyEquivalent: "")
                editParams.target = self
                editParams.representedObject = script.id.uuidString
                submenu.addItem(editParams)

                let rename = NSMenuItem(title: "Rename…",
                                        action: #selector(renameScript(_:)),
                                        keyEquivalent: "")
                rename.target = self
                rename.representedObject = script.id.uuidString
                submenu.addItem(rename)

                let delete = NSMenuItem(title: "Delete",
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

        let addItem = NSMenuItem(title: "Add a script…",
                                 action: #selector(addScript),
                                 keyEquivalent: "a")
        addItem.target = self
        menu.addItem(addItem)

        let openJSONItem = NSMenuItem(title: "Open scripts.json",
                                      action: #selector(openStorageJSON),
                                      keyEquivalent: "")
        openJSONItem.target = self
        menu.addItem(openJSONItem)

        // Variante affichée tant que la touche Option est maintenue.
        let revealJSONItem = NSMenuItem(title: "Show scripts.json",
                                        action: #selector(revealStorageJSON),
                                        keyEquivalent: "")
        revealJSONItem.target = self
        revealJSONItem.isAlternate = true
        revealJSONItem.keyEquivalentModifierMask = .option
        menu.addItem(revealJSONItem)

        let refreshItem = NSMenuItem(title: "Refresh",
                                     action: #selector(refreshFromDisk),
                                     keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())

        let alwaysTerminalItem = NSMenuItem(title: "Always run in terminal",
                                            action: #selector(toggleAlwaysRunInTerminal),
                                            keyEquivalent: "")
        alwaysTerminalItem.target = self
        alwaysTerminalItem.state = alwaysRunInTerminal ? .on : .off
        menu.addItem(alwaysTerminalItem)

        let alwaysShowItem = NSMenuItem(title: "Always show logs window at run",
                                        action: #selector(toggleAlwaysShowLogs),
                                        keyEquivalent: "")
        alwaysShowItem.target = self
        alwaysShowItem.state = alwaysShowLogsAtRun ? .on : .off
        menu.addItem(alwaysShowItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit",
                                  action: #selector(quit),
                                  keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: Actions

    @objc private func addScript() {
        let panel = NSOpenPanel()
        panel.title = "Choose one or more scripts"
        panel.message = "Select one or more .sh files (Cmd+click for multiple)."
        panel.prompt = "Add"
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.resolvesAliases = true

        if let shType = UTType(filenameExtension: "sh") {
            panel.allowedContentTypes = [shType]
        }

        NSApp.activate(ignoringOtherApps: true)

        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        var addedScripts: [Script] = []
        for url in panel.urls {
            let defaultName = url.deletingPathExtension().lastPathComponent
            let script = Script(name: defaultName, path: url.path)
            ScriptStore.shared.add(script)
            addedScripts.append(script)
        }
        rebuildMenu()

        // Ouvre l'éditeur de paramètres si un seul script a été ajouté. Pour
        // un import en lot, on évite la cascade de pop-ups — l'utilisateur
        // pourra éditer chacun via le sous-menu « Edit parameters… ».
        if addedScripts.count == 1, let script = addedScripts.first {
            showParamEditor(for: script)
        }
    }

    @objc private func editScriptParams(_ sender: NSMenuItem) {
        guard
            let idStr = sender.representedObject as? String,
            let id = UUID(uuidString: idStr),
            let script = ScriptStore.shared.script(for: id)
        else { return }
        showParamEditor(for: script)
    }

    /// Ouvre la fenêtre d'édition des @param pour ce script, pré-remplie avec
    /// les directives existantes (parse du fichier).
    private func showParamEditor(for script: Script) {
        let existing = ScriptHeaderParser.parseParams(scriptPath: script.path)
        let editor = ParamEditorWindowController(
            scriptName: script.name,
            scriptPath: script.path,
            initialParams: existing
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.paramEditors.removeAll { $0.window?.isVisible == false }
                self?.rebuildMenu()
            }
        }
        paramEditors.append(editor)
        editor.show()
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

        let params = ScriptHeaderParser.parseParams(scriptPath: script.path)

        var args: [String] = []
        if !params.isEmpty {
            guard let values = ParamInputDialog.collect(params: params, scriptName: script.name) else {
                return
            }
            // Si le nom du @param commence par '-' (ou '--'), c'est un flag :
            // on passe `-name value`. Sinon, on passe juste la valeur (positionnel).
            // Pour un flag dont la valeur est vide, on n'émet rien (flag optionnel non utilisé).
            for (param, value) in zip(params, values) {
                if param.name.hasPrefix("-") {
                    if !value.isEmpty {
                        args.append(param.name)
                        args.append(value)
                    }
                } else {
                    args.append(value)
                }
            }
        }

        // La pref globale « Always run in terminal » force le mode terminal,
        // même si l'utilisateur a cliqué sur « Run » plutôt que sur l'alternate
        // Option « Run in terminal ».
        let effectiveOpenInTerminal = openInTerminal || alwaysRunInTerminal

        if effectiveOpenInTerminal {
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
        // Si l'option globale « Always show logs window at run » est activée,
        // on force la création et l'affichage de la fenêtre maintenant.
        if alwaysShowLogsAtRun {
            let controller = ensureLogWindow(for: script)
            if !controller.isShown { controller.show() }
        }
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
        alert.messageText = "Rename script"
        alert.informativeText = "Choose a new display name."
        alert.alertStyle = .informational

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        textField.stringValue = script.name
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

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
        alert.messageText = "Delete this script?"
        alert.informativeText = "« \(script.name) » will be removed from the list. The original file will not be deleted."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
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

    @objc private func toggleAlwaysShowLogs() {
        alwaysShowLogsAtRun.toggle()
        rebuildMenu()
    }

    @objc private func toggleAlwaysRunInTerminal() {
        alwaysRunInTerminal.toggle()
        rebuildMenu()
    }

    // MARK: Script manquant

    private func handleMissingScript(_ script: Script) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Script not found"
        alert.informativeText =
            "The file no longer exists at:\n\n\(script.path)\n\nWhat would you like to do?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Choose a new path…")
        alert.addButton(withTitle: "Remove entry")
        alert.addButton(withTitle: "Cancel")

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
        panel.title = "Choose the new location for « \(script.name) »"
        panel.prompt = "Update"
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

    /// Handler invoqué quand l'utilisateur déclenche « Run with QuickScript… »
    /// sur une sélection de fichiers dans le Finder.
    @objc func runWithQuickScript(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let files = filePaths(from: pasteboard)
        guard !files.isEmpty else {
            error.pointee = "No file selected." as NSString
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.showScriptPicker(forFiles: files, contextPath: nil)
        }
    }

    /// Handler invoqué quand l'utilisateur déclenche « Run with QuickScript here… »
    /// (clic droit dans le vide d'une fenêtre du Finder ou sur le Bureau).
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
            alert.messageText = "No scripts to run"
            alert.informativeText = "Add a script first via the menu bar (« Add a script… »)."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            _ = alert.runModal()
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Run")
        alert.addButton(withTitle: "Cancel")

        if let context = contextPath {
            alert.messageText = "Run a script here"
            alert.informativeText =
                "The script will access the folder via $QS_CONTEXT_TARGET_PATH:\n\n\(context)"
        } else {
            alert.messageText = "Run a script"
            let fileLabel = files.count == 1
                ? "the selected file"
                : "the \(files.count) selected files"
            var detail = "The script will access \(fileLabel) via $QS_CONTEXT_FILE_PATH."
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
