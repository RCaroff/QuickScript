import Foundation

// ============================================================================
// MARK: - HeadlessMCPHost
// ============================================================================

/// Implémentation de `MCPToolHost` **sans AppKit**, utilisée par le transport
/// stdio (`--mcp-stdio`). N'a pas de menu ni de fenêtre : opère directement sur
/// `ConfigStore` (fichier `config.json`) et le dossier `scripts/`, et exécute
/// les scripts de façon synchrone via `Process` en capturant la sortie.
///
/// Recharge le store au début de chaque opération pour rester cohérent avec une
/// éventuelle instance GUI tournant en parallèle (qui partage le même
/// `config.json`).
final class HeadlessMCPHost: MCPToolHost {

    // MARK: Helpers de résolution / sérialisation

    private func resolveScript(_ target: String?) -> Script? {
        guard let target = target, !target.isEmpty else { return nil }
        if let uuid = UUID(uuidString: target), let s = ConfigStore.shared.script(for: uuid) {
            return s
        }
        return ConfigStore.shared.scripts.first { $0.name == target }
    }

    private func scriptParam(from dict: [String: Any]) -> ScriptParam? {
        guard let name = (dict["name"] as? String)?.trimmingCharacters(in: .whitespaces),
              !name.isEmpty else { return nil }
        let def = (dict["default"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let desc = (dict["description"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return ScriptParam(name: name, defaultValue: def, description: desc)
    }

    private func paramJSON(_ p: ScriptParam) -> [String: Any] {
        var d: [String: Any] = ["name": p.name]
        if let v = p.defaultValue { d["default"] = v }
        if let v = p.description { d["description"] = v }
        return d
    }

    private func scriptJSON(_ s: Script) -> [String: Any] {
        let params = ScriptHeaderParser.parseParams(scriptPath: s.path)
        return [
            "id": s.id.uuidString,
            "name": s.name,
            "path": s.path,
            "exists": FileManager.default.fileExists(atPath: s.path),
            "params": params.map(paramJSON)
        ]
    }

    // MARK: Outils

    func mcpListScripts() -> MCPToolOutcome {
        ConfigStore.shared.load()
        let scripts = ConfigStore.shared.scripts.map(scriptJSON)
        return .ok(["scripts": scripts, "count": scripts.count])
    }

    func mcpAddScript(name: String?, content: String?, params: [[String: Any]]) -> MCPToolOutcome {
        guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
            return .error("Le champ 'name' est requis.")
        }
        guard let content = content, !content.isEmpty else {
            return .error("Le champ 'content' est requis.")
        }

        let url = QSLog.uniqueScriptFileURL(forName: name)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            return .error("Écriture du fichier impossible : \(error.localizedDescription)")
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)

        let parsed = params.compactMap(scriptParam(from:))
        if !parsed.isEmpty {
            _ = ParamSerializer.write(parsed, toScriptAt: url.path)
        }

        // Recharge avant d'ajouter pour ne pas écraser des changements concurrents.
        ConfigStore.shared.load()
        let script = Script(name: name, path: url.path)
        ConfigStore.shared.add(script)

        return .ok(["ok": true, "script": scriptJSON(script)])
    }

    func mcpUpdateParams(target: String?, params: [[String: Any]]) -> MCPToolOutcome {
        ConfigStore.shared.load()
        guard let script = resolveScript(target) else {
            return .error("Script introuvable pour : \(target ?? "(vide)")")
        }
        guard FileManager.default.fileExists(atPath: script.path) else {
            return .error("Le fichier du script n'existe plus : \(script.path)")
        }
        let parsed = params.compactMap(scriptParam(from:))
        guard ParamSerializer.write(parsed, toScriptAt: script.path) else {
            return .error("Échec de la réécriture des @param dans le fichier.")
        }
        return .ok(["ok": true, "script": scriptJSON(script)])
    }

    func mcpRunScript(target: String?, values: [String: String], inTerminal: Bool) -> MCPToolOutcome {
        ConfigStore.shared.load()
        guard let script = resolveScript(target) else {
            return .error("Script introuvable pour : \(target ?? "(vide)")")
        }
        guard FileManager.default.fileExists(atPath: script.path) else {
            return .error("Le fichier du script n'existe plus : \(script.path)")
        }

        // Construit les arguments selon la convention flag/positionnel.
        let params = ScriptHeaderParser.parseParams(scriptPath: script.path)
        var args: [String] = []
        for p in params {
            let value = values[p.name] ?? p.defaultValue ?? ""
            if p.name.hasPrefix("-") {
                if !value.isEmpty { args.append(p.name); args.append(value) }
            } else {
                args.append(value)
            }
        }

        let proc = Process()
        let ext = (script.path as NSString).pathExtension.lowercased()
        if let interp = ScriptRunner.interpreter(for: ext) {
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            proc.arguments = [interp, script.path] + args
        } else if FileManager.default.isExecutableFile(atPath: script.path) {
            proc.executableURL = URL(fileURLWithPath: script.path)
            proc.arguments = args
        } else {
            proc.executableURL = URL(fileURLWithPath: "/bin/bash")
            proc.arguments = [script.path] + args
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        proc.environment = env

        do {
            try proc.run()
        } catch {
            return .error("Exécution impossible : \(error.localizedDescription)")
        }

        // Lit stderr en parallèle pour éviter un blocage si un pipe se remplit.
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        proc.waitUntilExit()

        var payload: [String: Any] = [
            "ok": proc.terminationStatus == 0,
            "exitCode": Int(proc.terminationStatus),
            "stdout": String(data: outData, encoding: .utf8) ?? "",
            "stderr": String(data: errData, encoding: .utf8) ?? "",
            "script": script.name
        ]
        if inTerminal {
            payload["note"] = "Le mode terminal n'est pas disponible en stdio headless ; le script a été exécuté en capturant la sortie."
        }
        return .ok(payload)
    }
}
