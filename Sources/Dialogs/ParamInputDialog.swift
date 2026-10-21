import Cocoa

/// Dialog modal de saisie des `@param` au lancement d'un script. Affiche un
/// contrôle adapté au type de chaque paramètre, retourne les valeurs (ordre
/// stable) :
/// - `string` → label + champ texte
/// - `bool`   → case à cocher (valeur "true" / "false")
/// - `enum`   → label + liste déroulante
enum ParamInputDialog {

    /// Un contrôle par paramètre, capable de restituer sa valeur.
    private enum Control {
        case text(NSTextField)
        case checkbox(NSButton)
        case popup(NSPopUpButton)

        var value: String {
            switch self {
            case .text(let f): return f.stringValue
            case .checkbox(let b): return b.state == .on ? "true" : "false"
            case .popup(let p): return p.titleOfSelectedItem ?? ""
            }
        }

        var view: NSView {
            switch self {
            case .text(let f): return f
            case .checkbox(let b): return b
            case .popup(let p): return p
            }
        }
    }

    /// Affiche le dialog. Renvoie les valeurs si l'utilisateur valide, nil sinon.
    static func collect(params: [ScriptParam], scriptName: String) -> [String]? {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Parameters for « \(scriptName) »"
        alert.informativeText = "Fill in the parameters before running the script."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Run")
        alert.addButton(withTitle: "Cancel")

        let width: CGFloat = 380
        let labelHeight: CGFloat = 16
        let fieldHeight: CGFloat = 22
        let popupHeight: CGFloat = 26
        let checkboxHeight: CGFloat = 18
        let rowSpacing: CGFloat = 6
        let blockSpacing: CGFloat = 14

        // Hauteur de chaque bloc selon le type.
        func blockHeight(_ p: ScriptParam) -> CGFloat {
            switch p.type {
            case .string: return labelHeight + rowSpacing + fieldHeight
            case .enumeration: return labelHeight + rowSpacing + popupHeight
            case .bool: return checkboxHeight
            }
        }
        let totalHeight = params.map(blockHeight).reduce(0, +)
            + CGFloat(max(params.count - 1, 0)) * blockSpacing

        let container = FlippedView(
            frame: NSRect(x: 0, y: 0, width: width, height: max(totalHeight, fieldHeight))
        )

        var controls: [Control] = []
        var y: CGFloat = 0

        for param in params {
            let labelText: String
            if let desc = param.description, !desc.isEmpty {
                labelText = "\(param.name) — \(desc)"
            } else {
                labelText = param.name
            }

            switch param.type {
            case .bool:
                let box = NSButton(checkboxWithTitle: labelText, target: nil, action: nil)
                box.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
                box.frame = NSRect(x: 0, y: y, width: width, height: checkboxHeight)
                box.state = param.effectiveDefault == "true" ? .on : .off
                container.addSubview(box)
                controls.append(.checkbox(box))

            case .enumeration(let options):
                addLabel(labelText, at: y, width: width, height: labelHeight, to: container)
                let popup = NSPopUpButton(
                    frame: NSRect(x: 0, y: y + labelHeight + rowSpacing, width: width, height: popupHeight),
                    pullsDown: false
                )
                popup.addItems(withTitles: options)
                popup.selectItem(withTitle: param.effectiveDefault)
                container.addSubview(popup)
                controls.append(.popup(popup))

            case .string:
                addLabel(labelText, at: y, width: width, height: labelHeight, to: container)
                let field = NSTextField(
                    frame: NSRect(x: 0, y: y + labelHeight + rowSpacing, width: width, height: fieldHeight)
                )
                field.placeholderString = param.name
                if let def = param.defaultValue { field.stringValue = def }
                container.addSubview(field)
                controls.append(.text(field))
            }

            y += blockHeight(param) + blockSpacing
        }

        // Tab order = ordre des contrôles ajoutés
        let views = controls.map { $0.view }
        if views.count > 1 {
            for i in 0..<views.count - 1 {
                views[i].nextKeyView = views[i + 1]
            }
            views.last?.nextKeyView = views.first
        }

        alert.accessoryView = container
        // Focus initial : premier champ texte s'il y en a un, sinon 1er contrôle.
        let firstText = controls.first { if case .text = $0 { return true } else { return false } }
        alert.window.initialFirstResponder = (firstText ?? controls.first)?.view

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        return controls.map { $0.value }
    }

    private static func addLabel(_ text: String, at y: CGFloat, width: CGFloat,
                                 height: CGFloat, to container: NSView) {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        label.frame = NSRect(x: 0, y: y, width: width, height: height)
        container.addSubview(label)
    }
}
