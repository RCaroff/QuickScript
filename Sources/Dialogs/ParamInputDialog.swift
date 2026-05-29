import Cocoa

/// Dialog modal de saisie des `@param` au lancement d'un script. Affiche un
/// label + text field par paramètre, retourne les valeurs (ordre stable).
enum ParamInputDialog {

    /// Affiche un dialog avec un text field par paramètre.
    /// Renvoie les valeurs si l'utilisateur valide, nil sinon.
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
