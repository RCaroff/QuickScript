import Foundation

/// Helpers de chemins pour les fichiers `.log` produits par chaque lancement.
///
/// Structure :
///   ~/Library/Application Support/QuickScript/logs/<script-name-sanitized>/<name>-yyyy-MM-dd_HHmmss.log
enum QSLog {

    /// Renvoie l'URL d'un nouveau fichier .log pour un lancement donné.
    /// Crée le sous-dossier par script à la volée.
    static func newLogFileURL(for script: Script) -> URL {
        let safe = sanitized(script.name)
        let dir = scriptLogDirectory(for: script)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd_HHmmss"
        let stamp = fmt.string(from: Date())
        return dir.appendingPathComponent("\(safe)-\(stamp).log")
    }

    /// Dossier dédié à un script, indépendamment d'un lancement particulier.
    static func scriptLogDirectory(for script: Script) -> URL {
        let dir = baseDirectory().appendingPathComponent(sanitized(script.name),
                                                         isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Dossier dédié aux scripts créés via le serveur MCP (`add_script`).
    /// `~/Library/Application Support/QuickScript/scripts/`
    static func scriptsFolder() -> URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport
            .appendingPathComponent("QuickScript", isDirectory: true)
            .appendingPathComponent("scripts", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Renvoie une URL de fichier `.sh` libre dans le dossier `scripts/`,
    /// dérivée d'un nom lisible et sanitisé. Évite les collisions en suffixant
    /// `-2`, `-3`, … si besoin.
    static func uniqueScriptFileURL(forName name: String) -> URL {
        let dir = scriptsFolder()
        var base = sanitized(name)
        if base.hasSuffix(".sh") { base = String(base.dropLast(3)) }
        if base.isEmpty { base = "script" }

        let fm = FileManager.default
        var candidate = dir.appendingPathComponent("\(base).sh")
        var counter = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base)-\(counter).sh")
            counter += 1
        }
        return candidate
    }

    static func baseDirectory() -> URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport
            .appendingPathComponent("QuickScript", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Remplace les caractères réservés du système de fichiers par `_`.
    private static func sanitized(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\")
        let parts = name.components(separatedBy: invalid)
        let joined = parts.joined(separator: "_")
        return joined.isEmpty ? "script" : joined
    }
}
