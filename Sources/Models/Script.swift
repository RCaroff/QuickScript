import Foundation

// ============================================================================
// MARK: - Script
// ============================================================================

/// Représentation d'un script importé par l'utilisateur dans QuickScript.
/// Persistée dans ~/Library/Application Support/QuickScript/config.json.
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

// ============================================================================
// MARK: - ScriptParam
// ============================================================================

/// Paramètre déclaré dans l'en-tête d'un script via la directive `# @param`.
/// Parsé par `ScriptHeaderParser`, sérialisé par `ParamSerializer`.
///
/// Syntaxe : `# @param NAME[:TYPE][=DEFAULT] [description]`
/// où TYPE vaut `string` (défaut), `bool` ou `enum(a|b|c)`.
struct ScriptParam {
    let name: String
    let defaultValue: String?
    let description: String?
    var type: ParamType = .string

    init(name: String, defaultValue: String?, description: String?, type: ParamType = .string) {
        self.name = name
        self.defaultValue = defaultValue
        self.description = description
        self.type = type
    }

    /// Valeur initiale à présenter dans le dialog / à utiliser si aucune
    /// valeur n'est fournie.
    var effectiveDefault: String {
        switch type {
        case .string:
            return defaultValue ?? ""
        case .bool:
            return ParamType.parseBool(defaultValue ?? "") == true ? "true" : "false"
        case .enumeration(let options):
            if let d = defaultValue, options.contains(d) { return d }
            return options.first ?? (defaultValue ?? "")
        }
    }

    /// Normalise une valeur fournie de l'extérieur (MCP, dialog) selon le type.
    /// Bool → "true"/"false" (accepte 1/0, yes/no, oui/non…).
    func normalized(_ value: String?) -> String {
        guard let value = value else { return effectiveDefault }
        switch type {
        case .string, .enumeration:
            return value
        case .bool:
            guard let b = ParamType.parseBool(value) else { return effectiveDefault }
            return b ? "true" : "false"
        }
    }
}

// ============================================================================
// MARK: - ParamType
// ============================================================================

/// Type d'un `@param`, qui détermine le contrôle affiché au lancement :
/// champ texte, case à cocher ou liste déroulante.
enum ParamType: Equatable {
    case string
    case bool
    case enumeration([String])

    /// Représentation textuelle utilisée dans le header du script
    /// (`string`, `bool`, `enum(a|b|c)`).
    var spec: String {
        switch self {
        case .string: return "string"
        case .bool: return "bool"
        case .enumeration(let options): return "enum(\(options.joined(separator: "|")))"
        }
    }

    /// Parse `string` / `bool` / `boolean` / `enum(a|b|c)` (insensible à la
    /// casse pour le mot-clé). Chaîne vide → `.string`. Renvoie nil si invalide.
    static func parse(_ raw: String) -> ParamType? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        let lower = s.lowercased()
        if s.isEmpty || lower == "string" || lower == "text" { return .string }
        if lower == "bool" || lower == "boolean" { return .bool }
        if lower.hasPrefix("enum(") && s.hasSuffix(")") {
            let inner = s.dropFirst("enum(".count).dropLast()
            let options = inner
                .split(separator: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return options.isEmpty ? nil : .enumeration(options)
        }
        return nil
    }

    static func parseBool(_ raw: String) -> Bool? {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "true", "yes", "y", "1", "oui", "on": return true
        case "false", "no", "n", "0", "non", "off", "": return false
        default: return nil
        }
    }
}
