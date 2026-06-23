import Foundation

/// Singleton de persistance JSON de toute la configuration QuickScript.
///
/// Fichier : `~/Library/Application Support/QuickScript/config.json`
/// Contenu : `AppConfig` (liste des `Script` + `Preferences`), encodé
/// pretty-printed avec clés triées.
///
/// Migration : si `config.json` n'existe pas encore mais que l'ancien
/// `scripts.json` (+ préférences en `UserDefaults`) est présent, on les importe
/// une fois puis on écrit `config.json`.
final class ConfigStore {
    static let shared = ConfigStore()

    /// Chemin du fichier JSON où la config est persistée.
    let storageURL: URL
    private let folderURL: URL

    private(set) var scripts: [Script] = []
    private(set) var preferences = Preferences()

    private init() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("QuickScript", isDirectory: true)
        if !fm.fileExists(atPath: folder.path) {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        self.folderURL = folder
        self.storageURL = folder.appendingPathComponent("config.json")
        load()
    }

    func load() {
        if let data = try? Data(contentsOf: storageURL),
           let cfg = try? JSONDecoder().decode(AppConfig.self, from: data) {
            scripts = cfg.scripts
            preferences = cfg.preferences
            return
        }
        // Pas de config.json : tente une migration depuis l'ancien format.
        migrateLegacyIfNeeded()
    }

    func save() {
        let cfg = AppConfig(scripts: scripts, preferences: preferences)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(cfg)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            NSLog("QuickScript: config save failed - \(error)")
        }
    }

    // MARK: Scripts

    func add(_ s: Script) { scripts.append(s); save() }
    func remove(id: UUID) { scripts.removeAll { $0.id == id }; save() }

    func update(_ s: Script) {
        if let idx = scripts.firstIndex(where: { $0.id == s.id }) {
            scripts[idx] = s
            save()
        }
    }

    func script(for id: UUID) -> Script? {
        return scripts.first(where: { $0.id == id })
    }

    // MARK: Préférences

    /// Mute les préférences puis persiste immédiatement.
    func updatePreferences(_ mutate: (inout Preferences) -> Void) {
        mutate(&preferences)
        save()
    }

    // MARK: Migration

    /// Importe l'ancien `scripts.json` + les `UserDefaults` historiques, puis
    /// écrit `config.json`. Ne touche pas à l'ancien fichier (laissé en place
    /// par prudence, mais plus jamais relu).
    private func migrateLegacyIfNeeded() {
        let legacyURL = folderURL.appendingPathComponent("scripts.json")
        var migratedAnything = false

        if let data = try? Data(contentsOf: legacyURL),
           let decoded = try? JSONDecoder().decode([Script].self, from: data) {
            scripts = decoded
            migratedAnything = true
        }

        let d = UserDefaults.standard
        let hadPrefs = d.object(forKey: "alwaysRunInTerminal") != nil
            || d.object(forKey: "alwaysShowLogsAtRun") != nil
            || d.object(forKey: "mcpServerEnabled") != nil
            || d.object(forKey: "mcpServerPort") != nil
        if hadPrefs {
            let port = d.integer(forKey: "mcpServerPort")
            preferences = Preferences(
                alwaysRunInTerminal: d.bool(forKey: "alwaysRunInTerminal"),
                alwaysShowLogsAtRun: d.bool(forKey: "alwaysShowLogsAtRun"),
                mcpServerEnabled: d.bool(forKey: "mcpServerEnabled"),
                mcpServerPort: port == 0 ? 8765 : port
            )
            migratedAnything = true
        }

        if migratedAnything {
            save()
        }
    }
}
