import Foundation

/// Singleton de persistance JSON des scripts importés.
///
/// Fichier : `~/Library/Application Support/QuickScript/scripts.json`
/// Format : tableau d'objets `Script` encodés pretty-printed avec clés triées.
final class ScriptStore {
    static let shared = ScriptStore()

    /// Chemin du fichier JSON où la liste des scripts est persistée.
    let storageURL: URL
    private(set) var scripts: [Script] = []

    private init() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("QuickScript", isDirectory: true)
        if !fm.fileExists(atPath: folder.path) {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        self.storageURL = folder.appendingPathComponent("scripts.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        if let decoded = try? JSONDecoder().decode([Script].self, from: data) {
            scripts = decoded
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(scripts)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            NSLog("QuickScript: save failed - \(error)")
        }
    }

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
}
