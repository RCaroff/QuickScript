import Cocoa

/// Fenêtre listant les paramètres d'un script dans un NSTableView. L'utilisateur
/// peut ajouter, supprimer, modifier et réordonner (drag&drop) les entrées. À
/// la validation, les directives `# @param` sont réécrites dans le fichier .sh
/// via `ParamSerializer`.
final class ParamEditorWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {

    private let scriptName: String
    private let scriptPath: String
    private var params: [EditableParam]
    private let onClose: (_ saved: Bool) -> Void

    private let tableView = NSTableView()
    private static let dragType = NSPasteboard.PasteboardType("com.rcaroff.quickscript.param-row")

    private let positionColID = NSUserInterfaceItemIdentifier("position")
    private let nameColID = NSUserInterfaceItemIdentifier("name")
    private let defaultColID = NSUserInterfaceItemIdentifier("default")
    private let descColID = NSUserInterfaceItemIdentifier("description")

    init(scriptName: String,
         scriptPath: String,
         initialParams: [ScriptParam],
         onClose: @escaping (_ saved: Bool) -> Void) {
        self.scriptName = scriptName
        self.scriptPath = scriptPath
        self.params = initialParams.map { EditableParam(from: $0) }
        self.onClose = onClose

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 440),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Parameters — \(scriptName)"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: UI

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // En-tête
        let title = NSTextField(labelWithString: "Parameters for « \(scriptName) »")
        title.font = NSFont.boldSystemFont(ofSize: 14)
        title.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(wrappingLabelWithString:
            "These lines will be written as « # @param … » directives in the script. " +
            "Prefix the name with « - » (e.g. -service) to pass the value as a flag " +
            "(-service value) instead of a positional argument. " +
            "Drag & drop to reorder.")
        subtitle.font = NSFont.systemFont(ofSize: 11)
        subtitle.textColor = NSColor.secondaryLabelColor
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        // Table
        setupTableColumns()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 24
        tableView.registerForDraggedTypes([Self.dragType])
        tableView.setDraggingSourceOperationMask([.move], forLocal: true)

        // Single-click sur une cellule éditable → entre directement en édition
        // (sans ça macOS exige un double-click sur NSTextField sans bordure,
        // ce qui n'est pas évident pour l'utilisateur).
        tableView.target = self
        tableView.action = #selector(tableCellClicked(_:))

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        // Boutons +/- (segmented style à la Finder)
        let addBtn = NSButton(title: "+",
                              target: self,
                              action: #selector(addRow))
        addBtn.bezelStyle = .smallSquare
        let removeBtn = NSButton(title: "−",
                                 target: self,
                                 action: #selector(removeSelectedRow))
        removeBtn.bezelStyle = .smallSquare

        addBtn.translatesAutoresizingMaskIntoConstraints = false
        removeBtn.translatesAutoresizingMaskIntoConstraints = false

        let addRemove = NSStackView(views: [addBtn, removeBtn])
        addRemove.orientation = .horizontal
        addRemove.spacing = 0
        addRemove.translatesAutoresizingMaskIntoConstraints = false

        // OK / Annuler
        let cancelBtn = NSButton(title: "Cancel",
                                 target: self,
                                 action: #selector(cancel))
        cancelBtn.bezelStyle = .rounded
        cancelBtn.keyEquivalent = "\u{1b}" // Esc

        let okBtn = NSButton(title: "Save",
                             target: self,
                             action: #selector(saveAndClose))
        okBtn.bezelStyle = .rounded
        okBtn.keyEquivalent = "\r" // Enter

        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        okBtn.translatesAutoresizingMaskIntoConstraints = false

        let okCancel = NSStackView(views: [cancelBtn, okBtn])
        okCancel.orientation = .horizontal
        okCancel.spacing = 8
        okCancel.translatesAutoresizingMaskIntoConstraints = false

        let bottomBar = NSStackView()
        bottomBar.orientation = .horizontal
        bottomBar.spacing = 8
        bottomBar.alignment = .centerY
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addArrangedSubview(addRemove)
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bottomBar.addArrangedSubview(spacer)
        bottomBar.addArrangedSubview(okCancel)

        contentView.addSubview(title)
        contentView.addSubview(subtitle)
        contentView.addSubview(scroll)
        contentView.addSubview(bottomBar)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            title.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            title.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            subtitle.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            subtitle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            scroll.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            scroll.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -12),

            bottomBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            bottomBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            bottomBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])

        tableView.reloadData()
    }

    private func setupTableColumns() {
        let posCol = NSTableColumn(identifier: positionColID)
        posCol.title = "#"
        posCol.width = 32
        posCol.minWidth = 28
        posCol.maxWidth = 40
        posCol.isEditable = false
        tableView.addTableColumn(posCol)

        let nameCol = NSTableColumn(identifier: nameColID)
        nameCol.title = "Name"
        nameCol.width = 140
        nameCol.minWidth = 80
        tableView.addTableColumn(nameCol)

        let defaultCol = NSTableColumn(identifier: defaultColID)
        defaultCol.title = "Default value"
        defaultCol.width = 140
        defaultCol.minWidth = 80
        tableView.addTableColumn(defaultCol)

        let descCol = NSTableColumn(identifier: descColID)
        descCol.title = "Description (optional)"
        descCol.width = 260
        descCol.minWidth = 100
        tableView.addTableColumn(descCol)
    }

    // MARK: Actions

    @objc private func addRow() {
        params.append(EditableParam())
        tableView.reloadData()
        let last = params.count - 1
        tableView.selectRowIndexes(IndexSet(integer: last), byExtendingSelection: false)
        tableView.scrollRowToVisible(last)
        // Focus sur le champ Nom (colonne d'index 1, après la colonne position).
        let nameColIndex = tableView.column(withIdentifier: nameColID)
        if nameColIndex >= 0,
           let cell = tableView.view(atColumn: nameColIndex,
                                     row: last,
                                     makeIfNecessary: false) as? NSTableCellView,
           let tf = cell.textField {
            window?.makeFirstResponder(tf)
        }
    }

    @objc private func removeSelectedRow() {
        let row = tableView.selectedRow
        guard row >= 0, row < params.count else { return }
        params.remove(at: row)
        tableView.reloadData()
    }

    @objc private func saveAndClose() {
        // Commit toute édition en cours (force l'envoi de l'action des NSTextField)
        window?.makeFirstResponder(nil)

        // Filtre les lignes sans nom — un @param sans nom n'a aucun sens
        let cleaned = params.filter {
            !$0.name.trimmingCharacters(in: .whitespaces).isEmpty
        }
        let asScriptParams = cleaned.map { $0.toScriptParam() }

        let ok = ParamSerializer.write(asScriptParams, toScriptAt: scriptPath)
        if !ok {
            let alert = NSAlert()
            alert.messageText = "Unable to write to the file"
            alert.informativeText = "Verify the script exists and is editable:\n\(scriptPath)"
            alert.addButton(withTitle: "OK")
            _ = alert.runModal()
            return
        }
        onClose(true)
        window?.close()
    }

    @objc private func cancel() {
        onClose(false)
        window?.close()
    }

    // MARK: NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        return params.count
    }

    func tableView(_ tableView: NSTableView,
                   pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString("\(row)", forType: Self.dragType)
        return item
    }

    func tableView(_ tableView: NSTableView,
                   validateDrop info: NSDraggingInfo,
                   proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        return dropOperation == .above ? .move : []
    }

    func tableView(_ tableView: NSTableView,
                   acceptDrop info: NSDraggingInfo,
                   row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        guard let items = info.draggingPasteboard.pasteboardItems,
              let s = items.first?.string(forType: Self.dragType),
              let oldIndex = Int(s),
              oldIndex >= 0, oldIndex < params.count else { return false }

        let item = params[oldIndex]
        let newIndex = row > oldIndex ? row - 1 : row
        params.remove(at: oldIndex)
        params.insert(item, at: newIndex)
        tableView.reloadData()
        return true
    }

    // MARK: NSTableViewDelegate

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        guard let column = tableColumn else { return nil }
        guard row >= 0 && row < params.count else { return nil }

        let p = params[row]
        let cell = NSTableCellView()
        let field = NSTextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.font = NSFont.systemFont(ofSize: 12)
        field.target = self
        field.action = #selector(cellTextChanged(_:))
        // Sans ça, l'action ne fire que sur Enter/Tab — pas à la perte de focus.
        field.cell?.sendsActionOnEndEditing = true

        switch column.identifier {
        case positionColID:
            field.stringValue = "\(row + 1)"
            field.isEditable = false
            field.isSelectable = false
            field.alignment = .center
            field.textColor = NSColor.secondaryLabelColor
        case nameColID:
            field.stringValue = p.name
            field.placeholderString = "name"
            field.isEditable = true
        case defaultColID:
            field.stringValue = p.defaultValue
            field.placeholderString = "default value"
            field.isEditable = true
        case descColID:
            field.stringValue = p.descText
            field.placeholderString = "description"
            field.isEditable = true
        default: break
        }

        cell.addSubview(field)
        cell.textField = field
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    @objc private func tableCellClicked(_ sender: NSTableView) {
        let col = sender.clickedColumn
        let row = sender.clickedRow
        guard col >= 0, row >= 0, row < params.count else { return }
        // Colonne position : non éditable, ignore
        if tableView.tableColumns[col].identifier == positionColID { return }
        // Demande le focus sur le NSTextField de la cellule cliquée
        if let cell = tableView.view(atColumn: col, row: row, makeIfNecessary: false) as? NSTableCellView,
           let tf = cell.textField {
            window?.makeFirstResponder(tf)
        }
    }

    @objc private func cellTextChanged(_ sender: NSTextField) {
        let row = tableView.row(for: sender)
        let col = tableView.column(for: sender)
        guard row >= 0, row < params.count,
              col >= 0, col < tableView.tableColumns.count else { return }

        let identifier = tableView.tableColumns[col].identifier
        let value = sender.stringValue
        let p = params[row]
        if identifier == nameColID { p.name = value }
        else if identifier == defaultColID { p.defaultValue = value }
        else if identifier == descColID { p.descText = value }
    }
}
