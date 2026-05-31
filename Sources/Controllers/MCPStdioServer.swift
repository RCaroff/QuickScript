import Foundation

// ============================================================================
// MARK: - MCPStdioServer
// ============================================================================

/// Transport **stdio** du serveur MCP (mode `--mcp-stdio`).
///
/// Le client (ex : Claude Desktop) lance le binaire QuickScript avec l'argument
/// `--mcp-stdio` ; le processus n'ouvre alors aucune UI. Les messages JSON-RPC
/// sont échangés en **JSON délimité par des sauts de ligne** : un objet JSON par
/// ligne sur stdin, une réponse par ligne sur stdout. Les logs vont sur stderr.
///
/// Aucune dépendance AppKit : le host est `HeadlessMCPHost`, et le cœur tourne
/// avec `dispatchToMain: false` (pas de runloop main en mode headless).
final class MCPStdioServer {

    private let core: MCPCore
    private let host = HeadlessMCPHost()

    init() {
        self.core = MCPCore(host: host, dispatchToMain: false)
    }

    /// Boucle bloquante : lit stdin ligne par ligne jusqu'à EOF.
    func run() {
        log("QuickScript MCP stdio prêt.")
        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            guard
                let data = trimmed.data(using: .utf8),
                let obj = try? JSONSerialization.jsonObject(with: data),
                let message = obj as? [String: Any]
            else {
                let err = MCPCore.jsonRPCError(id: nil, code: -32700, message: "Parse error")
                writeMessage(err)
                continue
            }

            if let response = core.handle(message) {
                writeMessage(response)
            }
            // Sinon : notification, aucune réponse à émettre.
        }
        log("QuickScript MCP stdio : EOF, arrêt.")
    }

    // MARK: I/O

    private func writeMessage(_ message: [String: Any]) {
        // Réponse sur une seule ligne (pas de pretty-print à ce niveau).
        guard var data = try? JSONSerialization.data(withJSONObject: message) else { return }
        data.append(0x0A) // \n
        FileHandle.standardOutput.write(data)
    }

    private func log(_ s: String) {
        FileHandle.standardError.write(Data(("[quickscript-mcp] " + s + "\n").utf8))
    }
}
