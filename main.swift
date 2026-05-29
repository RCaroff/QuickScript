import Cocoa

// QuickScript — point d'entrée.
// Toute la logique est dans Sources/ (Models, Controllers, Views, Dialogs, Helpers).

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // LSUIElement → pas d'icône Dock
app.run()
