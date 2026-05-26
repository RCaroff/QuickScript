#!/usr/bin/env bash
#
# Compile QuickScript en un .app bundle macOS prêt à lancer.
#
# Usage :
#   ./build.sh             # build dans ./build/QuickScript.app
#   ./build.sh --install   # build puis copie dans ~/Applications/
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

# Compilation
echo "▸ Compilation de main.swift…"
swiftc -O \
    -framework Cocoa \
    -o "${MACOS_DIR}/${APP_NAME}" \
    main.swift

# Info.plist
cp Info.plist "${APP_BUNDLE}/Contents/Info.plist"

# Icône : iconutil (macOS-only, fourni avec les Command Line Tools) compile
# l'iconset en .icns. Si l'iconset n'existe pas, on saute silencieusement —
# l'app sera fonctionnelle mais avec l'icône générique macOS.
if [ -d "icon/AppIcon.iconset" ] && command -v iconutil >/dev/null 2>&1; then
    echo "▸ Génération de AppIcon.icns…"
    iconutil -c icns icon/AppIcon.iconset -o "${RESOURCES_DIR}/AppIcon.icns"
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

# Options
for arg in "$@"; do
    case "$arg" in
        --install)
            DEST="$HOME/Applications"
            mkdir -p "$DEST"
            rm -rf "${DEST}/${APP_NAME}.app"
            cp -R "$APP_BUNDLE" "$DEST/"
            echo "📦 Installé dans : ${DEST}/${APP_NAME}.app"
            refresh_services
            ;;
        --run)
            echo "🚀 Lancement…"
            open "$APP_BUNDLE"
            refresh_services
            ;;
    esac
done
