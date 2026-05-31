import Cocoa

// QuickScript — point d'entrée.
// Toute la logique est dans Sources/ (Models, Controllers, Views, Dialogs, Helpers).

// Mode serveur MCP stdio : le client (ex : Claude Desktop) lance le binaire avec
// `--mcp-stdio`. On ne démarre alors aucune UI ; on sert MCP sur stdin/stdout.
if CommandLine.arguments.contains("--mcp-stdio") {
    MCPStdioServer().run()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // LSUIElement → pas d'icône Dock
app.run()
