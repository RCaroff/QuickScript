import Foundation
import Network

// ============================================================================
// MARK: - MCPToolOutcome
// ============================================================================

/// Résultat d'un appel d'outil MCP retourné par le `MCPToolHost`.
/// `payload` est sérialisé en JSON et renvoyé comme contenu texte au client.
struct MCPToolOutcome {
    let payload: [String: Any]
    let isError: Bool

    static func ok(_ payload: [String: Any]) -> MCPToolOutcome {
        MCPToolOutcome(payload: payload, isError: false)
    }
    static func error(_ message: String) -> MCPToolOutcome {
        MCPToolOutcome(payload: ["error": message], isError: true)
    }
}

// ============================================================================
// MARK: - MCPToolHost
// ============================================================================

/// Délégué métier du serveur MCP. Implémenté par `AppDelegate`.
///
/// ⚠️ Toutes ces méthodes sont appelées **sur le main thread** par le serveur
/// (via `DispatchQueue.main.sync`), car elles touchent à `ConfigStore`, au menu
/// et au lancement de scripts (AppKit).
protocol MCPToolHost: AnyObject {
    func mcpListScripts() -> MCPToolOutcome
    func mcpAddScript(name: String?, content: String?, params: [[String: Any]]) -> MCPToolOutcome
    func mcpUpdateParams(target: String?, params: [[String: Any]]) -> MCPToolOutcome
    func mcpRunScript(target: String?, values: [String: String], inTerminal: Bool) -> MCPToolOutcome
}

// ============================================================================
// MARK: - MCPServer
// ============================================================================

/// Serveur MCP local exposant les opérations sur les scripts à une IA cliente.
///
/// Transport : **Streamable HTTP** (POST de messages JSON-RPC sur `127.0.0.1:port`).
/// Implémentation minimale basée sur `Network.framework` (`NWListener`). Suffit
/// pour `initialize`, `tools/list` et `tools/call` ; le streaming SSE n'est pas
/// utilisé (réponses JSON simples, ce que la spec autorise).
///
/// Le serveur n'écoute que sur la loopback, donc accessible uniquement depuis
/// la machine locale.
final class MCPServer {

    private(set) var port: UInt16
    private let core: MCPCore

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "tv.fubo.quickscript.mcp")
    private(set) var isRunning = false

    /// Callback déclenché si le listener tombe en erreur (ex : port déjà pris).
    /// Appelé sur le main thread.
    var onFailure: ((String) -> Void)?

    init(port: UInt16, host: MCPToolHost) {
        self.port = port
        // Host GUI (AppDelegate) : les outils doivent s'exécuter sur le main thread.
        self.core = MCPCore(host: host, dispatchToMain: true)
    }

    // MARK: Cycle de vie

    func start() {
        guard !isRunning else { return }
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            reportFailure("Port invalide : \(port)")
            return
        }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // Loopback uniquement (sécurité : aucune exposition réseau).
        params.requiredInterfaceType = .loopback

        do {
            let listener = try NWListener(using: params, on: nwPort)
            self.listener = listener

            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.isRunning = true
                case .failed(let error):
                    self?.isRunning = false
                    self?.reportFailure("Listener failed: \(error.localizedDescription)")
                case .cancelled:
                    self?.isRunning = false
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] conn in
                self?.handle(connection: conn)
            }

            listener.start(queue: queue)
        } catch {
            reportFailure("Impossible de démarrer le serveur MCP : \(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private func reportFailure(_ message: String) {
        NSLog("QuickScript MCP: \(message)")
        DispatchQueue.main.async { [weak self] in
            self?.onFailure?(message)
        }
    }

    // MARK: Connexion HTTP

    private func handle(connection conn: NWConnection) {
        conn.start(queue: queue)
        receiveRequest(on: conn, buffer: Data())
    }

    /// Accumule les octets jusqu'à disposer des headers + (Content-Length) octets
    /// de corps, puis traite la requête.
    private func receiveRequest(on conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            guard let self = self else { conn.cancel(); return }

            var buffer = buffer
            if let data = data, !data.isEmpty {
                buffer.append(data)
            }

            if let error = error {
                NSLog("QuickScript MCP: receive error \(error)")
                conn.cancel()
                return
            }

            // Sépare headers / corps sur \r\n\r\n.
            guard let headerEnd = self.rangeOfDoubleCRLF(in: buffer) else {
                if isComplete { conn.cancel(); return }
                self.receiveRequest(on: conn, buffer: buffer)
                return
            }

            let headerData = buffer.subdata(in: 0..<headerEnd.lowerBound)
            let headerString = String(data: headerData, encoding: .utf8) ?? ""
            let (method, contentLength) = self.parseRequestLineAndLength(headerString)

            let bodyStart = headerEnd.upperBound
            let available = buffer.count - bodyStart

            if available < contentLength {
                if isComplete { conn.cancel(); return }
                self.receiveRequest(on: conn, buffer: buffer)
                return
            }

            let body = buffer.subdata(in: bodyStart..<(bodyStart + contentLength))
            self.respond(to: conn, httpMethod: method, body: body)
        }
    }

    private func rangeOfDoubleCRLF(in data: Data) -> Range<Data.Index>? {
        let sep = Data([0x0D, 0x0A, 0x0D, 0x0A]) // \r\n\r\n
        return data.range(of: sep)
    }

    private func parseRequestLineAndLength(_ headers: String) -> (method: String, contentLength: Int) {
        let lines = headers.components(separatedBy: "\r\n")
        let method = lines.first?.components(separatedBy: " ").first ?? "GET"
        var length = 0
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2,
               parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                length = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        return (method, length)
    }

    // MARK: Dispatch JSON-RPC

    private func respond(to conn: NWConnection, httpMethod: String, body: Data) {
        // Le transport Streamable HTTP ouvre parfois un GET pour le canal SSE
        // serveur→client. On ne l'utilise pas : 405.
        if httpMethod.uppercased() == "GET" {
            sendHTTP(on: conn, status: "405 Method Not Allowed", json: nil)
            return
        }

        guard
            let obj = try? JSONSerialization.jsonObject(with: body),
            let message = obj as? [String: Any]
        else {
            let err = MCPCore.jsonRPCError(id: nil, code: -32700, message: "Parse error")
            sendHTTP(on: conn, status: "200 OK", json: err)
            return
        }

        // Délègue tout le protocole JSON-RPC au cœur partagé.
        if let response = core.handle(message) {
            sendHTTP(on: conn, status: "200 OK", json: response)
        } else {
            // Notification (pas d'id) : on accuse réception sans corps.
            sendHTTP(on: conn, status: "202 Accepted", json: nil)
        }
    }

    private func sendHTTP(on conn: NWConnection, status: String, json: [String: Any]?) {
        var bodyData = Data()
        if let json = json {
            bodyData = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        }

        var header = "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: application/json\r\n"
        header += "Content-Length: \(bodyData.count)\r\n"
        header += "Connection: close\r\n"
        header += "\r\n"

        var response = Data(header.utf8)
        response.append(bodyData)

        conn.send(content: response, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }
}
