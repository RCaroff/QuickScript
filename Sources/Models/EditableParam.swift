import Foundation

/// Ligne de l'éditeur graphique — classe (référence) pour pouvoir muter
/// directement depuis les callbacks des `NSTextField` (par cellule).
/// Conversion vers/depuis `ScriptParam` qui est la struct sérialisée.
final class EditableParam {
    var name: String
    var defaultValue: String
    var descText: String
    /// Type sous forme texte : "string" (ou vide), "bool", "enum(a|b|c)".
    var typeText: String

    init(name: String = "", defaultValue: String = "", description: String = "", typeText: String = "") {
        self.name = name
        self.defaultValue = defaultValue
        self.descText = description
        self.typeText = typeText
    }

    convenience init(from p: ScriptParam) {
        self.init(name: p.name,
                  defaultValue: p.defaultValue ?? "",
                  description: p.description ?? "",
                  typeText: p.type == .string ? "" : p.type.spec)
    }

    /// Type parsé, ou nil si `typeText` est invalide.
    var parsedType: ParamType? { ParamType.parse(typeText) }

    func toScriptParam() -> ScriptParam {
        return ScriptParam(name: name,
                           defaultValue: defaultValue.isEmpty ? nil : defaultValue,
                           description: descText.isEmpty ? nil : descText,
                           type: parsedType ?? .string)
    }
}
