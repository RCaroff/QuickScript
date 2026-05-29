import Foundation

/// Ligne de l'éditeur graphique — classe (référence) pour pouvoir muter
/// directement depuis les callbacks des `NSTextField` (par cellule).
/// Conversion vers/depuis `ScriptParam` qui est la struct sérialisée.
final class EditableParam {
    var name: String
    var defaultValue: String
    var descText: String

    init(name: String = "", defaultValue: String = "", description: String = "") {
        self.name = name
        self.defaultValue = defaultValue
        self.descText = description
    }

    convenience init(from p: ScriptParam) {
        self.init(name: p.name,
                  defaultValue: p.defaultValue ?? "",
                  description: p.description ?? "")
    }

    func toScriptParam() -> ScriptParam {
        return ScriptParam(name: name,
                           defaultValue: defaultValue.isEmpty ? nil : defaultValue,
                           description: descText.isEmpty ? nil : descText)
    }
}
