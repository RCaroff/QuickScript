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
struct ScriptParam {
    let name: String
    let defaultValue: String?
    let description: String?
}
