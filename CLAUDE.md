# QuickScript — notes pour Claude

Ce document décrit l'app pour qu'un futur Claude (ou toi-même dans 6 mois) puisse rapidement faire évoluer le code sans se perdre.

## Qu'est-ce que c'est ?

QuickScript est un utilitaire macOS dans la barre des menus (status bar) qui permet d'enregistrer des scripts (bash, python, ruby, etc.) et de les lancer en un clic — soit silencieusement avec capture des logs, soit dans une fenêtre Terminal/iTerm, soit depuis le menu contextuel du Finder via NSServices.

C'est une app native **Swift + AppKit**, pas SwiftUI. `LSUIElement = true` → pas d'icône Dock, pas de menu bar en haut de l'écran.

## Structure du projet

```
QuickScript/
├── main.swift          ← tout le code Swift (~1500 lignes, mono-fichier volontairement)
├── Info.plist          ← métadonnées app : bundle ID, NSServices, URL scheme, etc.
├── build.sh            ← compile main.swift en .app bundle, install dans ~/Applications
├── README.md           ← documentation utilisateur
├── CLAUDE.md           ← ce fichier
├── test-scripts/       ← scripts bash d'exemple pour tester chaque feature
│   ├── new-file.sh, new-file-here.sh, files-info.sh,
│   ├── interactive-prompt.sh, error-demo.sh, silent-ok.sh,
│   ├── gh-switch-*.sh, flatten-folder.sh
└── build/              ← output du build (généré, gitignorable)
    └── QuickScript.app
```

Pas de Xcode project. La compilation passe par `swiftc` direct dans `build.sh`, qui crée ensuite manuellement le bundle `.app`.

## Anatomie de `main.swift`

Le fichier est mono pour simplicité. Les sections sont délimitées par des `// MARK: -` :

| Section | Contenu |
|---------|---------|
| `Modèle` | `Script` (Codable), `ScriptParam` |
| `Persistance JSON` | `ScriptStore` (singleton, ~/Library/Application Support/QuickScript/scripts.json) |
| `Parser de l'en-tête de script` | `ScriptHeaderParser` — lit les directives `# @param NAME[=DEFAULT] [description]` |
| `Dialog de saisie des paramètres` | `ParamInputDialog` — NSAlert avec N text fields générés depuis les @param |
| `Logs : fichier .log + fenêtre live` | `QSLog` (helpers de chemins), `LogWindowController` (NSWindow custom) |
| `Runner (exécution silencieuse)` | `ScriptRunner` — Process + PTY + capture + détection de prompt |
| `TerminalLauncher` | Mode alternate Option : lance dans Terminal.app/iTerm via AppleScript |
| `PTY` | Helper `PTY.open()` pour `posix_openpt` + `grantpt` + `unlockpt` + termios |
| `AppDelegate` | Status item, menu builder, handlers de tous les @objc, NSServices, URL scheme |

## Comment lire le flow

### Boot

1. `app.run()` lance le runloop AppKit
2. `AppDelegate.applicationDidFinishLaunching(_:)` :
   - `installEditMenu()` — main menu invisible avec Cut/Copy/Paste/Cmd+V… (sans ça, les NSAlert + NSTextField ne reçoivent pas les raccourcis)
   - crée le `NSStatusItem`
   - `NSApp.servicesProvider = self` + `NSUpdateDynamicServices()` pour activer les Services NSServices déclarés dans Info.plist

### Construction du menu

`rebuildMenu()` reconstruit l'intégralité du menu de la status bar à chaque mutation :
- Liste des scripts (depuis `ScriptStore.shared.scripts`)
- Pour chaque script : un `NSMenuItem` avec sous-menu (Exécuter, Exécuter dans le terminal *(alternate Option)*, Révéler, Show/Hide logs window, Renommer, Supprimer)
- Bottom : *Ajouter un script…*, *Ouvrir scripts.json* / *Afficher scripts.json (alternate Option)*, *Actualiser*, *Quitter*

Pattern important : **alternate Option** = duo de menu items avec le même `keyEquivalent` et le 2e a `isAlternate=true` + `keyEquivalentModifierMask=.option`. AppKit swap automatiquement la visibilité.

### Lancement d'un script

Point d'entrée unique : `AppDelegate.launch(script:contextFiles:contextPath:openInTerminal:)`

1. Vérifie l'existence du fichier (sinon `handleMissingScript`)
2. Parse les `@param` du script et affiche `ParamInputDialog.collect(...)` s'il y en a
3. Si `openInTerminal == true` (clic alternate Option) → `TerminalLauncher.run(...)`, terminé
4. Sinon → mode silencieux :
   - calcule l'URL du fichier `.log` via `QSLog.newLogFileURL(for: script)`
   - récupère la `LogWindowController` existante pour ce script si elle est dans `logWindows[script.id]`, et l'attache au logURL
   - crée `ScriptRunner` et appelle `run { ... }` qui retire l'instance de `runnersByID` à la fin

### Mode silencieux (ScriptRunner)

Tout passe par un **PTY** (pseudo-terminal) côté child, créé via `PTY.open()`. Le child reçoit le slave sur ses FDs 0/1/2 → bash `read -p`, Python `input()` etc. voient un TTY et imprime leurs prompts normalement. L'app lit/écrit sur le master FD.

Termios du slave : `~ECHO` (sinon les entrées clavier ré-apparaissent dans la sortie), `~ONLCR`, `~ICRNL`.

Le master est lu via `FileHandle.readabilityHandler` (callback async sur queue globale). Chaque chunk :
- est ajouté à `outputData` (pour l'alerte d'erreur)
- alimente `pendingPrompt` (buffer depuis le dernier `\n`)
- est écrit dans `logFileURL` + un `\n` (séparateur entre chunks, demandé par l'utilisateur)
- est envoyé à `logWindow?.append(_:)` si une fenêtre est attachée

Un `Timer` toutes les 250 ms vérifie `pendingPrompt` : si le contenu se termine par `: ? > ]` après ~350 ms d'inactivité, ou si inactivité > 2.5 s, on considère que c'est un prompt stdin et on affiche un `NSAlert` avec un text field. La réponse + `\n` est écrite sur le master FD.

### Mode terminal (TerminalLauncher)

Construit une commande shell unique :
```
export QS_CONTEXT_TARGET_PATH='...'; \
export QS_CONTEXT_FILE_PATH='...'; \
script -q -a '/path/to.log' /usr/bin/env bash 'script.sh' 'arg1' 'arg2'
```

Échappement single-quote bash (`'foo'\''bar'` pour gérer les apostrophes), puis échappement AppleScript (`\\` puis `\"`), puis :

```applescript
tell application "Terminal"
    activate
    do script "<command>"
end tell
```

(ou iTerm si présent dans `/Applications/iTerm.app` ou `~/Applications/iTerm.app`)

Le wrap `script -q -a` (utilitaire BSD `script(1)`) capture toute la session terminal — y compris les prompts interactifs — dans le fichier `.log`. C'est pourquoi le logging fonctionne aussi en mode terminal.

## Variables d'environnement exposées aux scripts

| Variable | Quand | Contenu |
|----------|-------|---------|
| `QS_CONTEXT_TARGET_PATH` | Quick Action « Exécuter avec QuickScript ici… » | Dossier visible dans Finder (`insertion location`) |
| `QS_CONTEXT_FILE_PATH` | Quick Action « Exécuter avec QuickScript… » sur sélection | Chemins sélectionnés, un par ligne (joints par `\n`) |
| `PYTHONUNBUFFERED=1` | Toujours (mode silencieux) | Force Python à flusher ses prompts immédiatement |
| `TERM=dumb` | Toujours (mode silencieux) | Évite les séquences ANSI de couleur dans la sortie |

Les `@param` du script sont passés en arguments CLI (`$1`, `$2`, …) — **jamais** mélangés avec les fichiers du Quick Action (qui ne sont pas dans argv).

## Persistance

`scripts.json` :
```json
[
  { "id": "UUID", "name": "Mon script", "path": "/abs/path/script.sh" }
]
```

Stocké dans `~/Library/Application Support/QuickScript/scripts.json` (chemin obtenu via `FileManager.urls(for:.applicationSupportDirectory)`). L'encoder utilise `[.prettyPrinted, .sortedKeys]`.

Le decoder de `Script` est **rétrocompatible** : tout champ inconnu (`silent`, `openInTerminal`, `showLogs`, etc. — anciens essais de design) est ignoré. Si tu ajoutes un nouveau champ booléen, mets-le avec `decodeIfPresent(...) ?? defaultValue` dans le `init(from:)` custom.

## Logs fichier

`~/Library/Application Support/QuickScript/logs/<script-name-assaini>/<script-name>-yyyy-MM-dd_HHmmss.log`

Un nouveau fichier à chaque lancement. Contient un header (script, args, env de contexte), le contenu brut stdout+stderr (PTY merge en mode silencieux ; `script(1)` capture en mode terminal), un footer (`Exit N at …`).

Le caractère `/` dans le nom du script est remplacé par `_` pour le sous-dossier (cf. `QSLog.sanitized(_:)`).

## Fenêtre de logs (`LogWindowController`)

Une instance par script, gardée dans `AppDelegate.logWindows: [UUID: LogWindowController]`. Créée à la demande (clic *Show logs window*), persiste jusqu'à la suppression du script ou la fermeture de l'app.

`isReleasedWhenClosed = false` → la croix native cache (ne détruit pas) → le contenu est préservé.

État explicite `isShown: Bool` (pas `window.isVisible` qui n'est pas encore false dans `windowWillClose`), avec callback `onVisibilityChanged` qui déclenche `rebuildMenu()` pour que le label oscille correctement entre *Show* et *Hide logs window*.

Au lancement d'un script, `launch()` regarde si une `LogWindowController` existe pour ce script ; si oui, il appelle `attachToRun(logFileURL:)` pour la mettre à jour, et passe la référence au `ScriptRunner`. Sinon, le runner écrit seulement dans le fichier `.log`.

## Quick Actions Finder

Déclarées dans Info.plist :
- `runWithQuickScript` (NSSendTypes: `public.file-url` + `NSFilenamesPboardType`) — sur sélection de fichiers
- `runWithQuickScriptInContext` (pas de NSSendTypes) — sans sélection, clic dans le vide

Handlers dans `AppDelegate` :
- `runWithQuickScript(_:userData:error:)` lit le pasteboard → `showScriptPicker(forFiles:contextPath: nil)`
- `runWithQuickScriptInContext(_:userData:error:)` interroge Finder via `NSAppleScript` (`insertion location as alias`) → `showScriptPicker(forFiles: [], contextPath: target)`

Le picker est un `NSAlert` + `NSPopUpButton` listant tous les scripts.

**⚠️ macOS Sequoia restreint l'affichage des NSServices** d'apps tierces dans le menu contextuel du Finder. Si ça ne marche pas chez l'utilisateur, regarder *Réglages Système → Clavier → Raccourcis clavier → Services → Fichiers et dossiers* pour activer manuellement. Un fallback en Quick Actions Automator (`.workflow` dans `~/Library/Services/`) a été tenté puis rollback — voir l'historique git si tu veux le refaire.

## Build et installation

```bash
./build.sh                # build dans ./build/QuickScript.app
./build.sh --run          # build + open
./build.sh --install      # build + copie dans ~/Applications + pbs -update
```

Le build :
1. `swiftc -O -framework Cocoa -o build/QuickScript.app/Contents/MacOS/QuickScript main.swift`
2. `cp Info.plist build/QuickScript.app/Contents/Info.plist`
3. `codesign --force --sign - "$APP_BUNDLE"` (signature ad-hoc, suffit pour exécution locale)

Pour rafraîchir les Services après modification de NSServices, `--install` appelle `/System/Library/CoreServices/pbs -update`.

## Permissions macOS à demander à l'utilisateur

Au premier lancement :
1. **Apple Events / Automation** pour Finder (interroger `insertion location`) — déclaré dans `NSAppleEventsUsageDescription`
2. **Apple Events / Automation** pour Terminal ou iTerm (mode terminal via `do script` AppleScript)

macOS pose la question au runtime au premier appel. Réglable ensuite dans *Réglages Système → Confidentialité et sécurité → Automatisation → QuickScript*.

## Pour faire évoluer l'app

### Ajouter une nouvelle entrée dans le menu d'un script

1. Va dans `rebuildMenu()` (cherche `// MARK: Menu` dans `AppDelegate`)
2. Ajoute un `NSMenuItem` dans le bloc `let submenu = NSMenu()...` au bon endroit
3. Crée la méthode `@objc private func maNouvelleAction(_ sender: NSMenuItem)` dans la zone Actions
4. Récupère l'UUID via `sender.representedObject as? String`

### Ajouter un nouveau champ persisté sur Script

1. Ajoute le champ dans `struct Script` avec une valeur par défaut
2. Mets-le dans `enum CodingKeys`
3. Dans `init(from decoder:)`, utilise `decodeIfPresent(...) ?? défaut` pour la rétrocompat
4. Le encoder synthétisé écrira le champ automatiquement

### Ajouter une nouvelle variable d'environnement aux scripts

- Mode silencieux : `ScriptRunner.run()` → modifier le bloc `env["MA_VAR"] = ...`
- Mode terminal : `TerminalLauncher.buildShellCommand(...)` → ajouter une ligne `parts.append("export MA_VAR=\(shellEscape(...));")`

### Modifier le parsing des @param

`ScriptHeaderParser.parseParam(line:)` — accepte actuellement `# @param NAME[=DEFAULT] [description]`. Pour ajouter une nouvelle directive (ex: `# @flag NAME`), copie le pattern.

### Ajouter un nouveau Quick Action

1. Dans Info.plist, ajoute un dict dans `NSServices`
2. `NSMessage` = nom du selector ObjC
3. Implémente `@objc func nomDuSelector(_ pasteboard:userData:error:)` dans AppDelegate
4. Appelle `showScriptPicker(forFiles:contextPath:)` avec les bons paramètres
5. Rebuild + `--install` + `pbs -update` + `killall Finder`

### Ajouter un nouveau type de script supporté

`interpreter(for:)` dans `ScriptRunner` ET dans `TerminalLauncher` — il y a une duplication volontaire. Ajoute le case correspondant à l'extension.

Mais avant ça, l'`NSOpenPanel` d'`addScript()` filtre actuellement uniquement `.sh` via `panel.allowedContentTypes = [UTType(filenameExtension: "sh")]`. Ajoute d'autres `UTType` si tu veux autoriser plus d'extensions à l'import.

## Pièges connus

### Le shell par défaut de macOS est zsh

Quand `Terminal.app` exécute `do script "..."`, c'est `zsh` qui interprète. Si tu génères du bash-spécifique (process substitution `<( ... )`), assure-toi que c'est aussi valide en zsh.

### isVisible en `windowWillClose`

`NSWindow.isVisible` reste `true` pendant l'appel à `windowWillClose(_:)`. Ne pas s'en servir pour calculer un état. Utiliser un flag interne mis à jour avant le callback. Voir `LogWindowController.isShown`.

### Concurrency PTY

Les chunks du PTY arrivent sur une queue globale (readabilityHandler). Pour partager l'état avec le main thread, utiliser la `queue` dédiée du `ScriptRunner` (`DispatchQueue` privée). Ne pas accéder à `outputData` / `pendingPrompt` hors de cette queue.

### Le shell hérité du child a `$PWD = /`

Quand macOS lance une app via LaunchServices, le `pwd` est `/`. Tout script lancé via `ScriptRunner` hérite de ce `$PWD=/`. Si un script utilise `$PWD` comme fallback (ex: ancien bug de `flatten-folder.sh`), c'est catastrophique. **Toujours préférer** `$QS_CONTEXT_TARGET_PATH` ou un `@param target_dir` explicite, et refuser les paths sensibles.

### Édition de scripts.json à la main pendant que l'app tourne

L'app ne surveille pas le fichier. Après édition externe, l'utilisateur doit cliquer *Actualiser* dans le menu, ce qui appelle `ScriptStore.shared.load()` + `rebuildMenu()`.

### Détection de prompt = heuristique

Le `Timer` de `checkForPrompt()` est heuristique (250 ms tick, 350 ms idle threshold, suffixes `: ? > ]`). Si un script écrit `Loading...` sans `\n` et fait du long travail, l'app va popper un faux dialog de prompt. L'utilisateur peut Annuler — mais c'est intrusif. Pas de bonne solution générale sans demander à l'utilisateur de modifier son script.

### `NSAppleScript` est synchrone et bloque le main thread

`script.executeAndReturnError(&err)` bloque pendant qu'AppleScript tourne. Sur le premier appel à un Service AppleScript (Finder, Terminal), macOS affiche un prompt de permission qui peut bloquer plusieurs secondes. Pas critique mais à savoir.

## Roadmap potentielle

Idées qui ont été discutées ou seraient logiques :
- Raccourcis clavier globaux par script
- Drag & drop pour réordonner les scripts dans le menu
- Mémorisation des dernières valeurs `@param` saisies par script
- Filtre / recherche dans le menu si beaucoup de scripts
- Bouton "Clear" dans la fenêtre de logs
- Bouton "Relancer" dans l'alerte d'erreur
- Quick Actions Automator (.workflow) pour les Macs où NSServices sont invisibles
- Détection de PTY size (TIOCSWINSZ) pour les scripts utilisant `tput` / curses

## Style

- Tout français côté UI et commentaires utilisateur (le projet est perso)
- Selectors et selectorsmsg peuvent être en anglais
- Pas d'emojis sauf `⚡` dans la status bar
- Une feature = idéalement un commit clair, mais pas de framework de tests

## Quand tu travailles avec Claude là-dessus

- L'app est petite (mono-fichier ~1500 LOC). N'aie pas peur de demander à Claude de relire tout le contexte pertinent avant d'éditer.
- Précise toujours **où** l'item de menu doit aller (menu principal ou sous-menu), et **comment** (action directe vs alternate Option vs toggle persisté).
- Si tu rebuilds et que la nouvelle version semble identique à l'ancienne, vérifie que macOS n'a pas mis en cache l'ancien `.app` (par ex. dans `~/Library/Application Support/QuickScript/` ou via LaunchServices). Au pire : `lsregister -kill ; lsregister -seed`.
