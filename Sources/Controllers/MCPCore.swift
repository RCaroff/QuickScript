import Foundation

// ============================================================================
// MARK: - MCPCore
// ============================================================================

/// Cœur protocolaire MCP, **indépendant du transport**.
///
/// Traite les messages JSON-RPC (`initialize`, `ping`, `tools/list`,
/// `tools/call`) et délègue l'exécution des outils à un `MCPToolHost`.
/// Utilisé à la fois par `MCPServer` (transport HTTP, GUI) et
/// `MCPStdioServer` (transport stdio, headless).
final class MCPCore {

    private weak var host: MCPToolHost?

    /// Si `true`, les appels d'outils sont exécutés via `DispatchQueue.main.sync`
    /// (nécessaire quand le host est l'`AppDelegate` GUI). Doit rester `false`
    /// en mode stdio headless (aucune runloop main active → deadlock sinon).
    private let dispatchToMain: Bool

    init(host: MCPToolHost, dispatchToMain: Bool) {
        self.host = host
        self.dispatchToMain = dispatchToMain
    }

    /// Traite un message JSON-RPC décodé.
    /// - Returns: la réponse à renvoyer, ou `nil` s'il s'agit d'une notification
    ///   (message sans `id`) qui n'attend pas de réponse.
    func handle(_ message: [String: Any]) -> [String: Any]? {
        let id = message["id"]
        let method = message["method"] as? String ?? ""
        let params = message["params"] as? [String: Any] ?? [:]

        // Notification (pas d'id) : pas de réponse.
        if id == nil {
            return nil
        }

        return dispatch(method: method, params: params, id: id)
    }

    // MARK: Dispatch

    private func dispatch(method: String, params: [String: Any], id: Any?) -> [String: Any] {
        switch method {
        case "initialize":
            let clientProtocol = params["protocolVersion"] as? String ?? "2025-06-18"
            return Self.jsonRPCResult(id: id, result: [
                "protocolVersion": clientProtocol,
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "QuickScript", "version": "1.0.0"]
            ])

        case "ping":
            return Self.jsonRPCResult(id: id, result: [String: Any]())

        case "tools/list":
            return Self.jsonRPCResult(id: id, result: ["tools": Self.toolDefinitions()])

        case "tools/call":
            return handleToolCall(params: params, id: id)

        default:
            return Self.jsonRPCError(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    private func handleToolCall(params: [String: Any], id: Any?) -> [String: Any] {
        guard let name = params["name"] as? String else {
            return Self.jsonRPCError(id: id, code: -32602, message: "Missing tool name")
        }
        let args = params["arguments"] as? [String: Any] ?? [:]

        guard let host = host else {
            return Self.jsonRPCError(id: id, code: -32603, message: "Host indisponible")
        }

        let run = { Self.runTool(name: name, args: args, host: host) }
        let outcome: MCPToolOutcome = dispatchToMain ? DispatchQueue.main.sync(execute: run) : run()

        let text = Self.jsonText(from: outcome.payload)
        return Self.jsonRPCResult(id: id, result: [
            "content": [["type": "text", "text": text]],
            "isError": outcome.isError
        ])
    }

    private static func runTool(name: String, args: [String: Any], host: MCPToolHost) -> MCPToolOutcome {
        switch name {
        case "list_scripts":
            return host.mcpListScripts()
        case "add_script":
            return host.mcpAddScript(
                name: args["name"] as? String,
                content: args["content"] as? String,
                params: args["params"] as? [[String: Any]] ?? []
            )
        case "update_params":
            return host.mcpUpdateParams(
                target: (args["id"] as? String) ?? (args["name"] as? String),
                params: args["params"] as? [[String: Any]] ?? []
            )
        case "run_script":
            var values: [String: String] = [:]
            if let raw = args["values"] as? [String: Any] {
                for (k, v) in raw { values[k] = String(describing: v) }
            }
            return host.mcpRunScript(
                target: (args["id"] as? String) ?? (args["name"] as? String),
                values: values,
                inTerminal: args["in_terminal"] as? Bool ?? false
            )
        default:
            return MCPToolOutcome.error("Outil inconnu : \(name)")
        }
    }

    // MARK: Définitions d'outils

    static func toolDefinitions() -> [[String: Any]] {
        let paramItemSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "name": ["type": "string",
                         "description": "Nom du paramètre. S'il commence par '-' (ex: -service), il est passé en flag (-service valeur) ; sinon positionnel ($1, $2…)."],
                "default": ["type": "string", "description": "Valeur par défaut (optionnel)."],
                "description": ["type": "string", "description": "Description libre (optionnel)."]
            ],
            "required": ["name"]
        ]

        return [
            [
                "name": "list_scripts",
                "description": "Liste les scripts enregistrés dans QuickScript (id, nom, chemin, et paramètres @param détectés).",
                "inputSchema": ["type": "object", "properties": [String: Any]()]
            ],
            [
                "name": "add_script",
                "description": "Crée un nouveau script shell dans QuickScript. Écrit le contenu fourni dans un fichier .sh, y injecte l'en-tête '# @param', puis l'enregistre. Renvoie l'id et le chemin du script créé.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string", "description": "Nom affiché dans le menu (sert aussi de base au nom de fichier)."],
                        "content": ["type": "string", "description": "Contenu complet du script, shebang inclus (ex: #!/usr/bin/env bash). Les @param seront injectés automatiquement, ne pas les écrire à la main."],
                        "params": ["type": "array", "description": "Paramètres déclarés du script.", "items": paramItemSchema]
                    ],
                    "required": ["name", "content"]
                ]
            ],
            [
                "name": "update_params",
                "description": "Remplace les directives '# @param' d'un script existant (réécrit l'en-tête du fichier .sh). Identifier le script par 'id' ou par 'name'.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string", "description": "UUID du script (prioritaire sur name)."],
                        "name": ["type": "string", "description": "Nom du script si l'id n'est pas fourni."],
                        "params": ["type": "array", "description": "Liste complète des paramètres (remplace les existants).", "items": paramItemSchema]
                    ],
                    "required": ["params"]
                ]
            ],
            [
                "name": "run_script",
                "description": "Lance un script enregistré avec des valeurs de paramètres (sans afficher de dialogue). Identifier par 'id' ou 'name'. Exécute du code sur la machine — à utiliser avec prudence.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string", "description": "UUID du script (prioritaire)."],
                        "name": ["type": "string", "description": "Nom du script si l'id n'est pas fourni."],
                        "values": ["type": "object", "description": "Dictionnaire {nom_param: valeur}. Les paramètres absents prennent leur valeur par défaut."],
                        "in_terminal": ["type": "boolean", "description": "true pour lancer dans Terminal/iTerm (mode GUI uniquement), sinon mode silencieux (défaut false)."]
                    ]
                ]
            ]
        ]
    }

    // MARK: Encodage JSON-RPC

    static func jsonRPCResult(id: Any?, result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result]
    }

    static func jsonRPCError(id: Any?, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }

    private static func jsonText(from payload: [String: Any]) -> String {
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
            let s = String(data: data, encoding: .utf8)
        else { return "{}" }
        return s
    }
}
