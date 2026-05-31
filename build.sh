#!/usr/bin/env bash
#
# Compile QuickScript en un .app bundle macOS prêt à lancer.
#
# Usage :
#   ./build.sh             # build dans ./build/QuickScript.app
#   ./build.sh --install   # build puis copie dans ~/Applications/ ET /Applications
#   ./build.sh --run       # build puis ouvre l'app
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="QuickScript"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
MACOS_DIR="${APP_BUNDLE}/Contents/MacOS"
RESOURCES_DIR="${APP_BUNDLE}/Contents/Resources"

# Vérifie la présence de swiftc
if ! command -v swiftc >/dev/null 2>&1; then
    echo "Erreur : swiftc introuvable." >&2
    echo "Installe les Command Line Tools : xcode-select --install" >&2
    exit 1
fi

# Nettoyage
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Compilation : collecte tous les .swift de Sources/ + main.swift
echo "▸ Compilation Swift…"
SOURCE_FILES=$(find Sources -name "*.swift" 2>/dev/null)
swiftc -O \
    -framework Cocoa \
    -framework Network \
    -o "${MACOS_DIR}/${APP_NAME}" \
    main.swift $SOURCE_FILES

# Info.plist
cp Info.plist "${APP_BUNDLE}/Contents/Info.plist"

# Icône : iconutil (macOS-only, fourni avec les Command Line Tools) compile
# l'iconset en .icns. Si l'iconset n'existe pas, on saute silencieusement —
# l'app sera fonctionnelle mais avec l'icône générique macOS.
if [ -d "icon/AppIcon.iconset" ] && command -v iconutil >/dev/null 2>&1; then
    echo "▸ Génération de AppIcon.icns…"
    iconutil -c icns icon/AppIcon.iconset -o "${RESOURCES_DIR}/AppIcon.icns"
fi

# Icône menu bar (template image) : copiée telle quelle dans Resources/.
# NSImage(named: "menu-icon") trouve les variantes @2x et @3x via la convention de nommage.
if [ -f "icon/menu-icon.png" ]; then
    echo "▸ Copie de l'icône menu bar…"
    cp icon/menu-icon.png "${RESOURCES_DIR}/menu-icon.png"
    [ -f "icon/menu-icon@2x.png" ] && cp icon/menu-icon@2x.png "${RESOURCES_DIR}/menu-icon@2x.png"
    [ -f "icon/menu-icon@3x.png" ] && cp icon/menu-icon@3x.png "${RESOURCES_DIR}/menu-icon@3x.png"
fi

# Signature ad-hoc pour éviter le quarantine sur certaines configs
echo "▸ Signature ad-hoc…"
codesign --force --sign - "$APP_BUNDLE" 2>/dev/null || true

echo ""
echo "✅ Build terminé : ${APP_BUNDLE}"

# Force la redécouverte du Service par macOS (pour le menu contextuel du Finder).
# Sans ça, le système peut mettre plusieurs minutes à voir le nouveau service.
refresh_services() {
    echo "▸ Rafraîchissement des Services macOS…"
    /System/Library/CoreServices/pbs -update 2>/dev/null || true
    # Optionnel : relancer Finder pour qu'il rescan immédiatement.
    # killall Finder 2>/dev/null || true
}

# macOS met l'icône en cache (LaunchServices + iconservices). Quand on remplace
# une app déjà installée, Finder/Dock continuent souvent d'afficher l'ancienne
# icône (ou la générique). On force la redécouverte du bundle et on relance Dock
# + Finder pour qu'ils relisent l'AppIcon.icns.
#   $1 = chemin du .app installé
#   $2 = "sudo" si l'opération nécessite les droits root (cas /Applications)
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
refresh_icon_cache() {
    local dest="$1"
    local maybe_sudo="${2:-}"
    echo "▸ Invalidation du cache d'icônes pour ${dest}…"
    # Bump la date de modif du bundle : signal à LaunchServices que ça a changé.
    ${maybe_sudo} touch "$dest" 2>/dev/null || true
    # Ré-enregistre le bundle auprès de LaunchServices.
    if [ -x "$LSREGISTER" ]; then
        ${maybe_sudo} "$LSREGISTER" -f "$dest" 2>/dev/null || true
    fi
}

# Relance Dock et Finder une seule fois en fin d'install pour repeindre l'icône.
restart_ui_services() {
    echo "▸ Relance de Dock et Finder (rafraîchit l'affichage de l'icône)…"
    killall Dock 2>/dev/null || true
    killall Finder 2>/dev/null || true
}

# Options
for arg in "$@"; do
    case "$arg" in
        --install)
            # Installe dans ~/Applications (sans sudo)
            USER_DEST="$HOME/Applications"
            mkdir -p "$USER_DEST"
            rm -rf "${USER_DEST}/${APP_NAME}.app"
            cp -R "$APP_BUNDLE" "$USER_DEST/"
            echo "📦 Installé dans : ${USER_DEST}/${APP_NAME}.app"
            refresh_icon_cache "${USER_DEST}/${APP_NAME}.app"

            # Installe aussi dans /Applications (Macintosh HD) — écrase l'existant.
            # Nécessite sudo car /Applications est protégé. macOS demande le
            # mot de passe via prompt -p ; il suffit de l'entrer une fois.
            SYSTEM_DEST="/Applications"
            echo "▸ Installation dans ${SYSTEM_DEST} (sudo requis)…"
            sudo rm -rf "${SYSTEM_DEST}/${APP_NAME}.app"
            sudo cp -R "$APP_BUNDLE" "$SYSTEM_DEST/"
            echo "📦 Installé dans : ${SYSTEM_DEST}/${APP_NAME}.app"
            refresh_icon_cache "${SYSTEM_DEST}/${APP_NAME}.app" "sudo"

            refresh_services
            restart_ui_services
            ;;
        --run)
            echo "🚀 Lancement…"
            open "$APP_BUNDLE"
            refresh_services
            ;;
    esac
done
