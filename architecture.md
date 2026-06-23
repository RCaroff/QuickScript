# Architecture de QuickScript

Ce document décrit l'organisation interne du code après le refactoring MVC.
Il complète `CLAUDE.md` qui couvre les conventions, le build et les pièges.
Quand tu modifies une feature, commence par identifier dans quel(s) fichier(s)
elle vit grâce au tableau "fichier → rôle" plus bas, puis suis les flows pour
comprendre les interactions.

## Vue d'ensemble

QuickScript est une app **AppKit native**, mono-binaire, sans dépendance externe.
L'architecture suit un découpage MVC strict :

- **Modèles** (`Sources/Models/`) — structures de données + persistance JSON.
  Aucun import d'AppKit.
- **Vues** (`Sources/Views/`) — composants UI génériques réutilisables.
  Imports AppKit, pas de logique métier.
- **Dialogs** (`Sources/Dialogs/`) — assistants modaux jetables (NSAlert
  enrichis), retournent une valeur à l'appelant.
- **Controllers** (`Sources/Controllers/`) — fenêtres persistantes (NSWindowController)
  et orchestrateurs (AppDelegate, ScriptRunner, TerminalLauncher).
- **Helpers** (`Sources/Helpers/`) — utilitaires sans état : parsers,
  sérialiseurs, chemins, accès POSIX bas niveau.

Le point d'entrée `main.swift` est minimal : il instancie `AppDelegate` et
lance le runloop AppKit. Toute la logique vit dans `Sources/`.

## Arborescence détaillée

```
QuickScript/
├── main.swift                  ← point d'entrée, 10 lignes
├── Info.plist                  ← bundle ID, NSServices, icône
├── build.sh                    ← swiftc + bundle .app + iconutil
├── icon/                       ← icon.svg + AppIcon.iconset/
├── test-scripts/               ← scripts bash d'exemple
└── Sources/
    ├── Models/
    │   ├── Script.swift
    │   ├── AppConfig.swift
    │   ├── ConfigStore.swift
    │   └── EditableParam.swift
    ├── Views/
    │   └── FlippedView.swift
    ├── Dialogs/
    │   └── ParamInputDialog.swift
    ├── Controllers/
    │   ├── AppDelegate.swift
    │   ├── ScriptRunner.swift
    │   ├── TerminalLauncher.swift
    │   ├── LogWindowController.swift
    │   └── ParamEditorWindowController.swift
    └── Helpers/
        ├── ScriptHeaderParser.swift
        ├── ParamSerializer.swift
        ├── ANSIParser.swift
        ├── QSLog.swift
        └── PTY.swift
```

## Tableau "fichier → rôle"

| Fichier | Rôle | Dépendances |
|---------|------|-------------|
| `Models/Script.swift` | `struct Script` (Codable id+name+path) + `struct ScriptParam` | Foundation |
| `Models/AppConfig.swift` | `AppConfig {scripts, preferences}` + `Preferences` | `Script` |
| `Models/ConfigStore.swift` | Singleton persistance JSON (`config.json` : scripts + préférences) | `AppConfig` |
| `Models/EditableParam.swift` | Classe ref-type mutable utilisée par l'éditeur | `ScriptParam` |
| `Helpers/ScriptHeaderParser.swift` | Lit les `# @param NAME[=DEFAULT] desc` dans un .sh | `ScriptParam` |
| `Helpers/ParamSerializer.swift` | Réécrit les `# @param` dans le .sh (en place ou après shebang) | `ScriptParam` |
| `Helpers/ANSIParser.swift` | Convertit séquences ANSI SGR → `NSAttributedString` | AppKit (NSFont/NSColor) |
| `Helpers/QSLog.swift` | Chemins `~/Library/Application Support/QuickScript/logs/<script>/...` | `Script` |
| `Helpers/PTY.swift` | `posix_openpt` + `grantpt` + `unlockpt` + termios | Darwin |
| `Views/FlippedView.swift` | `NSView` avec `isFlipped = true` (coords top-down) | AppKit |
| `Dialogs/ParamInputDialog.swift` | `NSAlert` avec N text fields générés depuis les `@param` | `ScriptParam`, `FlippedView` |
| `Controllers/ScriptRunner.swift` | Exécution silencieuse via PTY, capture, détection de prompt, alerte d'erreur | `PTY`, `QSLog`, `ANSIParser`, `LogWindowController` |
| `Controllers/TerminalLauncher.swift` | Exécution dans Terminal.app / iTerm via AppleScript, wrap `script(1)` | `QSLog`, `Script` |
| `Controllers/LogWindowController.swift` | Fenêtre persistante par script, popup historique, ANSI rendering | `ANSIParser`, `QSLog` |
| `Controllers/ParamEditorWindowController.swift` | NSTableView pour ajouter/réordonner les `@param` | `EditableParam`, `ParamSerializer` |
| `Controllers/AppDelegate.swift` | Coordinateur : status item, menu, NSServices, cycle de vie | tous les controllers + helpers |

## Flow principal : lancement d'un script

```
       User clique « Run » dans le sous-menu
                    │
                    ▼
        AppDelegate.runScript(_:)
                    │
                    ▼
        AppDelegate.launch(script:contextFiles:contextPath:openInTerminal:)
                    │
                    │  1. Vérifie l'existence du fichier
                    │     (sinon handleMissingScript)
                    │
                    │  2. ScriptHeaderParser.parseParams(scriptPath:)
                    │     ─────────────────────────────────────────
                    │     Lit les # @param du fichier .sh
                    │
                    │  3. Si @param présents :
                    │     ParamInputDialog.collect(params:scriptName:)
                    │     ─────────────────────────────────────────
                    │     Modal NSAlert avec N text fields
                    │     → user valide → values: [String]
                    │
                    │  4. Construit args[] selon convention flag-style
                    │     (name commence par "-" → "-name value", sinon "value")
                    │
                    ▼
       openInTerminal ?
                    │
        ┌───────────┴───────────┐
        │ true                  │ false (mode silencieux)
        ▼                       ▼
TerminalLauncher.run(...)    Si alwaysShowLogsAtRun :
        │                       AppDelegate.ensureLogWindow(for:)
        │                       → controller.show()
        │
        │  Construit cmd shell  QSLog.newLogFileURL(for: script)
        │  (export QS_*; cmd)   ↓
        │                       ScriptRunner(script:args:contextFiles:
        │  Wrap avec script(1)   contextPath:logFileURL:logWindow:)
        │  pour capture log     ↓
        │                       runner.run { onFinish }
        │  AppleScript →
        │  Terminal.app/iTerm   ↓
                                Cycle PTY :
                                - openPTY() → master/slave
                                - process.standardInput=slave
                                - process.standardOutput=slave
                                - process.standardError=slave
                                - Close slave côté parent après run()
                                - Lecture async via readabilityHandler
                                  → chunks → onOutput(_:)
                                    - Append à outputData
                                    - Write au logFileURL
                                    - logWindow?.append(_:) avec ANSIParser
                                - Timer 250ms : checkForPrompt()
                                  → si idle + buffer non-vide
                                    → NSAlert input + write sur master
                                - handleTermination() à la fin :
                                  - Drain master
                                  - Close file handle
                                  - Si exit ≠ 0 : showErrorAlert
                                  - logWindow?.appendInfoLine("→ done"/"→ error")
                                  - onFinish() → AppDelegate retire du runnersByID
```

## Flow : Quick Action depuis le Finder

Deux services déclarés dans Info.plist :

### Sur sélection de fichiers (`runWithQuickScript`)

```
User clique « Run with QuickScript… » dans Services
        ↓
AppDelegate.runWithQuickScript(_:userData:error:)
        ↓
filePaths(from: pasteboard)  ← lit public.file-url + legacy
        ↓
showScriptPicker(forFiles: files, contextPath: nil)
        ↓
NSAlert + NSPopUpButton listant les scripts
        ↓
launch(script: chosen, contextFiles: files, contextPath: nil)
        ↓
ScriptRunner reçoit contextFiles → env["QS_CONTEXT_FILE_PATH"] = paths.joined("\n")
```

### Clic droit dans le vide (`runWithQuickScriptInContext`)

```
User clique « Run with QuickScript here… »
        ↓
AppDelegate.runWithQuickScriptInContext(_:userData:error:)
        ↓
currentFinderInsertionPath()  ← NSAppleScript → Finder
        ↓
showScriptPicker(forFiles: [], contextPath: target)
        ↓
launch(script: chosen, contextFiles: [], contextPath: target)
        ↓
ScriptRunner reçoit contextPath → env["QS_CONTEXT_TARGET_PATH"] = path
```

## Cycle de vie des fenêtres

`AppDelegate` détient des références fortes sur trois collections, ce qui
empêche la désallocation prématurée :

| Collection | Type | Vie |
|------------|------|-----|
| `runnersByID` | `[ObjectIdentifier: ScriptRunner]` | Pendant l'exécution d'un script (retiré dans `onFinish`) |
| `logWindows` | `[UUID: LogWindowController]` | De la première ouverture jusqu'à la suppression du script (`deleteScript`) |
| `paramEditors` | `[ParamEditorWindowController]` | Pendant que la fenêtre d'édition est visible (purgée dans le callback `onClose`) |

`LogWindowController` utilise `isReleasedWhenClosed = false` → la croix native
**cache** la fenêtre, elle n'est pas désallouée. Son contenu est préservé pour
réouverture via le menu.

Un flag interne `isShown: Bool` est maintenu manuellement (pas calculé depuis
`window.isVisible`) parce que `isVisible` n'est pas encore false dans
`windowWillClose(_:)`. Le callback `onVisibilityChanged` reconstruit le menu
pour que le toggle « Show/Hide logs window » reflète le bon état.

## Conventions

### Niveaux d'accès Swift

- **Par défaut `internal`** (no modifier) — visible dans tout le module
  QuickScript.
- **`private`** sur les méthodes/propriétés internes à un type. Pour les
  selectors `@objc`, `@objc private func` reste accessible via le runtime ObjC.
- Aucun `public`, `open` — l'app n'est pas une lib.

### Threading

- **Main thread** uniquement pour AppKit (UI, NSAlert, NSWindow, NSTextView).
- `ScriptRunner` utilise une `DispatchQueue` privée (`queue`) pour protéger
  les buffers partagés entre le `readabilityHandler` du PTY (thread global)
  et les vérifications du timer (main thread). Toujours `queue.sync { … }`
  pour lire/écrire `outputData`, `pendingPrompt`, `lastOutputAt`.
- Les méthodes UI à appeler depuis un thread non-main passent par
  `DispatchQueue.main.async`.

### Conventions de naming

- Strings UI **en anglais**. Commentaires en français.
- Noms de variables et de méthodes **en anglais** sauf dans les directives
  utilisateur (genre `# @param`) où le nom est libre.
- Selectors ObjC : `@objc func camelCaseAvec(_ sender: Any)` quand exposés
  via menu/button target.
- Préfixe `QS_` pour les variables d'environnement exposées aux scripts.

### Fichiers

- **Un type principal = un fichier** sauf petits types associés (ex: `Script` +
  `ScriptParam` cohabitent dans `Script.swift` car ils partagent le sujet).
- **`MARK: -`** uniquement pour les sections internes longues (cas des gros
  controllers).

## Comment ajouter une feature courante

### Nouvelle entrée dans le menu de la status bar

→ `Controllers/AppDelegate.swift`, méthode `rebuildMenu()`. Ajouter une
`NSMenuItem` + son handler `@objc private func`.

### Nouvelle entrée dans le sous-menu d'un script

→ Idem, dans la boucle `for script in scripts` à l'intérieur de `rebuildMenu()`.

### Nouveau champ persisté sur `Script`

→ `Models/Script.swift`. Ajouter une `var newField: T` avec valeur par défaut
dans l'init désigné. Dans `init(from:)`, utiliser `decodeIfPresent(...) ??
default` pour la rétrocompat avec les anciens JSON.

### Nouvelle variable d'environnement exposée aux scripts

→ Deux endroits :
- **Mode silencieux** : `Controllers/ScriptRunner.swift`, dans `run()`,
  bloc qui construit `env`.
- **Mode terminal** : `Controllers/TerminalLauncher.swift`, dans
  `buildShellCommand(...)`, ajouter `parts.append("export VAR=...;")`.

### Nouveau parser dans l'en-tête de script (`# @directive`)

→ `Helpers/ScriptHeaderParser.swift`. Ajouter un cas dans la boucle de parsing
similaire à celui de `@param`.

### Nouveau type d'interpréteur (`.rs`, `.go`, etc.)

→ Deux endroits (duplication volontaire pour découpler les deux modes
d'exécution) :
- `Controllers/ScriptRunner.swift` : `interpreter(for:)`
- `Controllers/TerminalLauncher.swift` : `interpreter(for:)`

Penser aussi à étendre le filtre `allowedContentTypes` du `NSOpenPanel` dans
`Controllers/AppDelegate.swift` (méthode `addScript()`).

### Nouvelle Quick Action / NSService

→ Trois étapes :
1. `Info.plist` : ajouter un dict dans `NSServices` avec `NSMessage = nom du selector`.
2. `Controllers/AppDelegate.swift` : implémenter `@objc func nomDuSelector(_:userData:error:)`.
3. Rebuild + `pbs -update` + `killall Finder` pour rafraîchir.

## Build

Le `build.sh` collecte automatiquement tous les `.swift` :

```bash
SOURCE_FILES=$(find Sources -name "*.swift")
swiftc -O -framework Cocoa -o build/QuickScript.app/Contents/MacOS/QuickScript main.swift $SOURCE_FILES
```

Tu n'as donc rien à modifier dans `build.sh` quand tu ajoutes un fichier dans
`Sources/`.
