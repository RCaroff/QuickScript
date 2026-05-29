import Foundation

/// Parse les directives `# @param` placées en tête d'un script.
///
/// Convention reconnue :
///
///   # @param NAME[=DEFAULT] [description libre]
///   #@param NAME            (sans espace après #, accepté)
///   // @param NAME          (pour des scripts en JS notamment)
///
/// Le parser lit la tête du fichier et s'arrête à la première ligne non
/// commentée / non vide / non shebang.
enum ScriptHeaderParser {

    static func parseParams(scriptPath: String) -> [ScriptParam] {
        guard
            let data = try? Data(contentsOf: URL(fileURLWithPath: scriptPath)),
            let content = String(data: data, encoding: .utf8)
        else { return [] }

        var params: [ScriptParam] = []
        let lines = content.components(separatedBy: .newlines).prefix(80)

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#!") { continue }            // shebang
            if line.hasPrefix("#") || line.hasPrefix("//") {
                if let param = parseParam(line: line) {
                    params.append(param)
                }
                continue
            }
            // Première ligne de code : on s'arrête.
            break
        }

        return params
    }

    private static func parseParam(line: String) -> ScriptParam? {
        // Supprime les marqueurs de commentaire de tête.
        var body = line
        for prefix in ["//", "#"] {
            if body.hasPrefix(prefix) {
                body = String(body.dropFirst(prefix.count))
                break
            }
        }
        body = body.trimmingCharacters(in: .whitespaces)

        // Doit commencer par @param
        guard body.lowercased().hasPrefix("@param") else { return nil }
        body = String(body.dropFirst("@param".count)).trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return nil }

        // Première "parole" = spec (NAME ou NAME=DEFAULT), reste = description
        let parts = body.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let spec = String(parts[0])
        let description = parts.count > 1
            ? String(parts[1]).trimmingCharacters(in: .whitespaces)
            : nil

        // Sépare NAME / DEFAULT
        if let eq = spec.firstIndex(of: "=") {
            let name = String(spec[..<eq])
            let def = String(spec[spec.index(after: eq)...])
            guard !name.isEmpty else { return nil }
            return ScriptParam(name: name, defaultValue: def, description: description)
        } else {
            return ScriptParam(name: spec, defaultValue: nil, description: description)
        }
    }
}
