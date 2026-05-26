# QuickScript

Petit utilitaire macOS qui vit dans la barre des menus et permet d'enregistrer des scripts (bash, python, ruby, node, ...) pour les **exécuter silencieusement en un clic**, sans terminal.

## Comportement (v2)

L'app fait apparaître `⚡` dans la barre des menus. Pendant qu'un ou plusieurs scripts tournent, le titre devient `⚡(N)`.

Quand tu cliques sur un script dans le menu :

- Si le script déclare des **paramètres** via `# @param`, une fenêtre s'ouvre avec un text field par paramètre. La valeur entrée est passée au script comme argument (`$1`, `$2`, ...).
- Sinon, le script démarre directement, en arrière-plan.
- **stdout / stderr** sont capturés. Aucune fenêtre n'apparaît tant que le script ne produit pas d'erreur.
- Si le script lit `stdin` (`read` en bash, `input()` en python...), l'app le détecte automatiquement et ouvre une fenêtre native avec un text field. La réponse est envoyée à `stdin` du script.
- Si le script termine avec un **code de sortie ≠ 0**, une alerte s'affiche avec stdout + stderr dans une zone de texte scrollable et un bouton « Copier les logs ».
- Si le script termine avec **code 0**, c'est silencieux : tu ne vois rien.

Le sous-menu de chaque entrée permet de **révéler dans le Finder**, **renommer**, ou **supprimer**. Si le fichier a été déplacé/supprimé depuis l'import, l'app propose au clic de relier le script ou de retirer l'entrée.

## Déclarer des paramètres : `# @param`

Place une ou plusieurs lignes en tête de script (après le shebang, avant le code) :

```bash
#!/usr/bin/env bash
# @param filename=note.txt   Nom du fichier
# @param content             Contenu (laisser vide pour fichier vide)
```

Syntaxe :

```
# @param NAME[=DEFAULT] [description libre jusqu'à la fin de la ligne]
```

- `NAME` : nom du paramètre (affiché comme label)
- `=DEFAULT` (optionnel) : valeur pré-remplie dans le text field
- Description (optionnelle) : tout texte qui suit, affiché à côté du label

Le parser accepte aussi `// @param` (utile pour les scripts JS).

L'ordre de déclaration = l'ordre dans lequel les valeurs sont passées au script (`$1`, `$2`, ...).

## Détection des prompts stdin (heuristique)

L'app monitore le buffer stdout. Si le script écrit du texte **sans saut de ligne final** et reste **idle plus de ~350 ms**, et que le texte se termine par `:` `?` `>` ou `]` (typiquement `Name: ` ou `Continue ? `), une fenêtre de saisie s'ouvre. Au-delà de 2,5 s d'inactivité, l'app prompte même sans caractère « prompt-like ».

Quirks à connaître :
- **Python** : l'app force `PYTHONUNBUFFERED=1` pour que `input("Name: ")` flushe le prompt avant de bloquer. Sans ça, Python attendrait un `\n` qui ne viendrait jamais.
- Si ton script imprime une longue ligne progressive sans `\n` (barre de progression, etc.), il peut être confondu avec un prompt — clique « Annuler le script » et ajoute un `\n` ou refacto pour utiliser des paramètres `@param`.

## Build

Prérequis : les Command Line Tools (`xcode-select --install`).

```bash
cd QuickScript
./build.sh             # produit build/QuickScript.app
./build.sh --run       # build puis ouvre l'app
./build.sh --install   # copie dans ~/Applications/
```

## Quick Actions dans le Finder

QuickScript déclare deux Services système :

### « Exécuter avec QuickScript… » — sur une sélection de fichiers

Clic droit sur un ou plusieurs fichiers dans le Finder → **Services** → **Exécuter avec QuickScript…**. Un picker apparaît pour choisir le script ; les chemins des fichiers sélectionnés sont exposés au script via la variable d'environnement `QS_CONTEXT_FILE_PATH` (un chemin par ligne).

Exemple — fichier unique :

```bash
file="$QS_CONTEXT_FILE_PATH"
echo "Selected: $file"
```

Exemple — sélection multiple, itération :

```bash
while IFS= read -r f; do
    echo "Processing $f"
done <<< "$QS_CONTEXT_FILE_PATH"
```

Les arguments CLI restent réservés aux valeurs des `@param` du script — la Quick Action ne les pollue plus.

### « Exécuter avec QuickScript ici… » — clic droit dans le vide

Clic droit dans une zone vide d'une fenêtre du Finder ou du Bureau → **Services** → **Exécuter avec QuickScript ici…**. Idem pour le picker, mais cette fois le chemin du dossier courant est exposé au script via la variable d'environnement `QS_CONTEXT_TARGET_PATH` (pas en argument CLI).

Exemple dans un script bash :

```bash
target="${QS_CONTEXT_TARGET_PATH:-$HOME/Desktop}"
touch "$target/nouveau-fichier.txt"
```

Pour récupérer le dossier visible, QuickScript interroge le Finder via AppleScript (`insertion location`). macOS demande la permission d'automation au premier déclenchement — accepte, c'est ponctuel. Réglable plus tard dans *Réglages Système → Confidentialité et sécurité → Automatisation*.

### Faire apparaître le Service

Sur macOS le menu Services n'est rafraîchi qu'occasionnellement. Si tu ne le vois pas après le build :

```bash
./build.sh --install   # copie l'app dans ~/Applications + rafraîchit pbs
```

Si ça ne suffit pas :

```bash
/System/Library/CoreServices/pbs -update
killall Finder        # relance Finder pour qu'il rescan
```

Le Service peut aussi être désactivé : *Réglages Système → Clavier → Raccourcis clavier → Services → Fichiers et dossiers*, vérifier que « Exécuter avec QuickScript… » est coché.

## Scripts de test fournis

Dans `test-scripts/` :

- `new-file.sh` — `@param` (target_dir + filename + content), crée un fichier
- `interactive-prompt.sh` — prompts runtime (3x `read -rp`)
- `error-demo.sh` — sort en erreur (code 1) avec stdout/stderr, déclenche l'alerte
- `silent-ok.sh` — exécution silencieuse complète (`touch` + exit 0)
- `files-info.sh` — démontre la Quick Action « sur sélection » : lit `$QS_CONTEXT_FILE_PATH` et log les fichiers reçus sur `~/Desktop/quickscript-files.log`
- `new-file-here.sh` — démontre la Quick Action « ici » : crée un fichier dans `$QS_CONTEXT_TARGET_PATH`

Pour les tester : `Ajouter un script…` → choisir un des fichiers → cliquer sur l'entrée nouvellement apparue dans le menu. Pour `files-info.sh`, après l'avoir ajouté, fais clic droit sur n'importe quel fichier du Finder → Services → Exécuter avec QuickScript… → choisis `files-info`.

## Stockage

Liste des scripts persistée dans :

```
~/Library/Application Support/QuickScript/scripts.json
```

JSON lisible et éditable à la main si besoin.

## Interpréteurs reconnus

| extension | interpréteur |
|-----------|--------------|
| `.py` | `python3` |
| `.sh`, `.bash` | `bash` |
| `.zsh` | `zsh` |
| `.rb` | `ruby` |
| `.js`, `.mjs` | `node` |
| `.pl` | `perl` |
| `.php` | `php` |
| autre, bit exécutable + shebang | exec direct |

Tous sont lancés via `/usr/bin/env`, donc tout interpréteur trouvable dans le `PATH` hérité de l'app fonctionnera.

## Pistes pour la suite

- Raccourcis clavier globaux par script
- Icônes / emoji custom par entrée
- Drag & drop pour réordonner
- Mémorisation des dernières valeurs de paramètres
- Variante PTY (pseudo-terminal) pour les scripts qui n'aiment pas tourner hors TTY
# QuickScript
# QuickScript
