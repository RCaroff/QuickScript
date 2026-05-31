#!/usr/bin/env bash
#
# Redimensionne les images sélectionnées dans le Finder via QuickScript.
#
# Source des images, par ordre de priorité :
#   1. @param path                    (rempli dans le dialog QuickScript)
#   2. $QS_CONTEXT_FILE_PATH          (Quick Action « Exécuter avec
#                                      QuickScript… » sur sélection Finder ;
#                                      un chemin par ligne)
#
# Paramètres :
#   - width  : largeur cible en pixels  (laisser vide pour conserver le ratio)
#   - height : hauteur cible en pixels  (laisser vide pour conserver le ratio)
#   - path   : chemin explicite d'une image (vide = utilise
#              $QS_CONTEXT_FILE_PATH)
#
# Au moins l'un des deux doit être renseigné. Si un seul est fourni, sips
# conserve le ratio en calculant l'autre côté.
#
# Sortie :
#   Chaque image est dupliquée à côté de l'original avec un suffixe
#   `_WxH` (par ex. `photo.jpg` → `photo_800x600.jpg`). Les originaux
#   ne sont jamais modifiés.
#
# @param width  Largeur cible en pixels (vide = ratio conservé)
# @param height  Hauteur cible en pixels (vide = ratio conservé)
# @param path  Chemin de l'image (vide = sélection Finder)
#
set -euo pipefail

width="${1:-}"
height="${2:-}"
path_param="${3:-}"

# --- Validation des paramètres ---------------------------------------------

if [[ -z "$width" && -z "$height" ]]; then
    echo "Erreur : renseigne au moins width ou height." >&2
    exit 1
fi

is_positive_int() { [[ "$1" =~ ^[0-9]+$ && "$1" -gt 0 ]]; }

if [[ -n "$width" ]] && ! is_positive_int "$width"; then
    echo "Erreur : width doit être un entier positif (reçu : « $width »)." >&2
    exit 1
fi
if [[ -n "$height" ]] && ! is_positive_int "$height"; then
    echo "Erreur : height doit être un entier positif (reçu : « $height »)." >&2
    exit 1
fi

# --- Résolution des fichiers à traiter -------------------------------------

# Si l'utilisateur a fourni un path explicite via le dialog, on l'utilise
# (une seule image). Sinon on retombe sur $QS_CONTEXT_FILE_PATH (multi-ligne).
if [[ -n "$path_param" ]]; then
    source_list="$path_param"
elif [[ -n "${QS_CONTEXT_FILE_PATH:-}" ]]; then
    source_list="$QS_CONTEXT_FILE_PATH"
else
    echo "Erreur : aucune image reçue." >&2
    echo "Sélectionne une ou plusieurs images dans le Finder et lance le" >&2
    echo "script via « Exécuter avec QuickScript… », ou remplis le" >&2
    echo "paramètre path dans le dialog." >&2
    exit 1
fi

# Suffixe de sortie : `_WxH`, `_Wx` ou `_xH` selon ce qui a été fourni.
suffix="_${width}x${height}"

# --- Construction des arguments sips ---------------------------------------

sips_args=()
if [[ -n "$width" && -n "$height" ]]; then
    # `--resampleHeightWidth` : note l'ordre H W (héritage sips).
    sips_args=(--resampleHeightWidth "$height" "$width")
elif [[ -n "$width" ]]; then
    sips_args=(--resampleWidth "$width")
else
    sips_args=(--resampleHeight "$height")
fi

# --- Traitement ------------------------------------------------------------

processed=0
skipped=0
failed=0

while IFS= read -r src; do
    [[ -z "$src" ]] && continue

    # Expansion ~ → $HOME pour les paths saisis à la main.
    src="${src/#\~/$HOME}"

    if [[ ! -f "$src" ]]; then
        echo "Ignoré (introuvable) : $src" >&2
        skipped=$((skipped + 1))
        continue
    fi

    # Filtre rapide sur l'extension pour éviter d'invoquer sips sur des
    # fichiers texte. sips supporte jpg/jpeg/png/tiff/gif/bmp/heic/webp.
    ext_lc=$(printf '%s' "${src##*.}" | tr '[:upper:]' '[:lower:]')
    case "$ext_lc" in
        jpg|jpeg|png|tif|tiff|gif|bmp|heic|heif|webp) ;;
        *)
            echo "Ignoré (extension non supportée) : $src" >&2
            skipped=$((skipped + 1))
            continue
            ;;
    esac

    dir=$(dirname "$src")
    name=$(basename "$src")
    base="${name%.*}"
    ext=""
    [[ "$name" == *.* ]] && ext=".${name##*.}"

    dest="$dir/${base}${suffix}${ext}"

    # Anti-collision : si une cible existe déjà, on incrémente.
    n=1
    while [[ -e "$dest" ]]; do
        dest="$dir/${base}${suffix}-${n}${ext}"
        n=$((n + 1))
    done

    echo "→ $src"
    if sips "${sips_args[@]}" "$src" --out "$dest" >/dev/null; then
        echo "  ✓ $dest"
        processed=$((processed + 1))
    else
        echo "  ✗ échec sips" >&2
        failed=$((failed + 1))
    fi
done <<< "$source_list"

echo ""
echo "Traitées : $processed"
[[ "$skipped" -gt 0 ]] && echo "Ignorées : $skipped"
[[ "$failed"  -gt 0 ]] && echo "Échecs   : $failed"

# Exit non-zéro s'il y a eu un échec, pour que QuickScript affiche l'alerte
# d'erreur en mode silencieux.
[[ "$failed" -eq 0 ]]
