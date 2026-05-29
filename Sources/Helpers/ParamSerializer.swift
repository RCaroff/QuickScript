import Foundation

/// Réécrit les directives `# @param` directement dans le fichier source du
/// script. Préserve le reste du contenu : si des `@param` existent déjà, ils
/// sont remplacés en place ; sinon, le bloc est inséré juste après le shebang.
enum ParamSerializer {

    /// Renvoie true si le fichier a pu être réécrit.
    static func write(_ params: [ScriptParam], toScriptAt path: String) -> Bool {
        guard let original = try? String(contentsOfFile: path, encoding: .utf8) else {
            return false
        }

        var lines = original.components(separatedBy: "\n")
        var paramIndices: [Int] = []

        // Repère les lignes @param existantes dans le header (avant la 1ʳᵉ ligne
        // de code).
        for (i, raw) in lines.enumerated() {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("#!") { continue }
            if trimmed.hasPrefix("#") || trimmed.hasPrefix("//") {
                if isParamLine(trimmed) { paramIndices.append(i) }
                continue
            }
            break // première ligne de code
        }

        let newLines = params.map(format)

        // Retire les anciennes en ordre décroissant pour préserver les indices.
        for idx in paramIndices.sorted(by: >) {
            lines.remove(at: idx)
        }

        // Position d'insertion
        let insertAt: Int
        if let first = paramIndices.first {
            insertAt = first
        } else if lines.first?.trimmingCharacters(in: .whitespaces).hasPrefix("#!") == true {
            // Après le shebang, et si possible après une ligne vide existante.
            if lines.count > 1 && lines[1].trimmingCharacters(in: .whitespaces).isEmpty {
                insertAt = 2
            } else {
                insertAt = 1
            }
        } else {
            insertAt = 0
        }

        lines.insert(contentsOf: newLines, at: insertAt)

        // Si pas de @param existants et qu'aucune ligne vide ne suit, en insère
        // une pour aérer.
        if paramIndices.isEmpty && !newLines.isEmpty {
            let afterIdx = insertAt + newLines.count
            if afterIdx < lines.count && !lines[afterIdx].trimmingCharacters(in: .whitespaces).isEmpty {
                lines.insert("", at: afterIdx)
            }
        }

        let newContent = lines.joined(separator: "\n")
        do {
            try newContent.write(toFile: path, atomically: true, encoding: .utf8)
            return true
        } catch {
            NSLog("QuickScript: unable to write @param - \(error)")
            return false
        }
    }

    private static func isParamLine(_ trimmed: String) -> Bool {
        var body = trimmed
        for prefix in ["//", "#"] {
            if body.hasPrefix(prefix) {
                body = String(body.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        return body.lowercased().hasPrefix("@param")
    }

    private static func format(_ p: ScriptParam) -> String {
        var s = "# @param \(p.name)"
        if let def = p.defaultValue, !def.isEmpty {
            s += "=\(def)"
        }
        if let desc = p.description, !desc.isEmpty {
            s += "  \(desc)"
        }
        return s
    }
}
