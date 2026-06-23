import Foundation

// ============================================================================
// MARK: - Preferences
// ============================================================================

/// Préférences globales de l'utilisateur, persistées dans `config.json`.
///
/// Remplace l'ancien stockage en `UserDefaults`. Les décodeurs sont tolérants
/// aux clés manquantes (`decodeIfPresent ?? défaut`) pour la rétrocompatibilité
/// et l'ajout futur de champs.
struct Preferences: Codable {
    /// Tout clic sur « Run » est traité comme « Run in terminal ».
    var alwaysRunInTerminal: Bool = false
    /// La fenêtre de logs est forcée à s'ouvrir à chaque lancement.
    var alwaysShowLogsAtRun: Bool = false
    /// Le serveur MCP (transport HTTP) est activé.
    var mcpServerEnabled: Bool = false
    /// Port du serveur MCP HTTP (loopback). Défaut 8765.
    var mcpServerPort: Int = 8765

    init(alwaysRunInTerminal: Bool = false,
         alwaysShowLogsAtRun: Bool = false,
         mcpServerEnabled: Bool = false,
         mcpServerPort: Int = 8765) {
        self.alwaysRunInTerminal = alwaysRunInTerminal
        self.alwaysShowLogsAtRun = alwaysShowLogsAtRun
        self.mcpServerEnabled = mcpServerEnabled
        self.mcpServerPort = mcpServerPort
    }

    enum CodingKeys: String, CodingKey {
        case alwaysRunInTerminal, alwaysShowLogsAtRun, mcpServerEnabled, mcpServerPort
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        alwaysRunInTerminal = try c.decodeIfPresent(Bool.self, forKey: .alwaysRunInTerminal) ?? false
        alwaysShowLogsAtRun = try c.decodeIfPresent(Bool.self, forKey: .alwaysShowLogsAtRun) ?? false
        mcpServerEnabled = try c.decodeIfPresent(Bool.self, forKey: .mcpServerEnabled) ?? false
        let port = try c.decodeIfPresent(Int.self, forKey: .mcpServerPort) ?? 8765
        mcpServerPort = port == 0 ? 8765 : port
    }
}

// ============================================================================
// MARK: - AppConfig
// ============================================================================

/// Forme sur disque de `config.json` : toute la configuration QuickScript de
/// l'utilisateur (liste des scripts + préférences globales).
struct AppConfig: Codable {
    var scripts: [Script] = []
    var preferences: Preferences = Preferences()

    init(scripts: [Script] = [], preferences: Preferences = Preferences()) {
        self.scripts = scripts
        self.preferences = preferences
    }

    enum CodingKeys: String, CodingKey {
        case scripts, preferences
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        scripts = try c.decodeIfPresent([Script].self, forKey: .scripts) ?? []
        preferences = try c.decodeIfPresent(Preferences.self, forKey: .preferences) ?? Preferences()
    }
}
