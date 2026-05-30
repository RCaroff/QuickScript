#!/usr/bin/env bash
#
# Rogne les bords des images sélectionnées dans le Finder via QuickScript.
#
# Source des images, par ordre de priorité :
#   1. @param path                    (rempli dans le dialog QuickScript)
#   2. $QS_CONTEXT_FILE_PATH          (Quick Action « Exécuter avec
#                                      QuickScript… » sur sélection Finder ;
#                                      un chemin par ligne)
#
# Paramètres :
#   - left   : pixels à retirer du bord gauche
#   - right  : pixels à retirer du bord droit
#   - top    : pixels à retirer du bord haut
#   - bottom : pixels à retirer du bord bas
#   - path   : chemin explicite d'une image (vide = utilise
#              $QS_CONTEXT_FILE_PATH)
#
# Au moins une des quatre valeurs de rognage doit être > 0. Les valeurs
# vides sont traitées comme 0.
#
# Sortie :
#   Chaque image est dupliquée à côté de l'original avec un suffixe
#   `_crop` (par ex. `photo.jpg` → `photo_crop.jpg`). Les originaux ne
#   sont jamais modifiés.
#
# @param left=0  Pixels à rogner à gauche
# @param right=0  Pixels à rogner à droite
# @param top=0  Pixels à rogner en haut
# @param bottom=0  Pixels à rogner en bas
# @param path  Chemin de l'image (vide = sélection Finder)
#
set -euo pipefail

left="${1:-0}"
right="${2:-0}"
top="${3:-0}"
bottom="${4:-0}"
path_param="${5:-}"

# --- Validation des paramètres ---------------------------------------------

# Une valeur vide est tolérée et interprétée comme 0.
[[ -z "$left"   ]] && left=0
[[ -z "$right"  ]] && right=0
[[ -z "$top"    ]] && top=0
[[ -z "$bottom" ]] && bottom=0

is_non_negative_int() { [[ "$1" =~ ^[0-9]+$ ]]; }

for pair in "left:$left" "right:$right" "top:$top" "bottom:$bottom"; do
    name="${pair%%:*}"
    val="${pair##*:}"
    if ! is_non_negative_int "$val"; then
        echo "Erreur : $name doit être un entier ≥ 0 (reçu : « $val »)." >&2
        exit 1
    fi
done

if (( left + right + top + bottom == 0 )); then
    echo "Erreur : renseigne au moins une valeur de rognage > 0." >&2
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

    ext_lc=$(printf '%s' "${src##*.}" | tr '[:upper:]' '[:lower:]')
    case "$ext_lc" in
        jpg|jpeg|png|tif|tiff|gif|bmp|heic|heif|webp) ;;
        *)
            echo "Ignoré (extension non supportée) : $src" >&2
            skipped=$((skipped + 1))
            continue
            ;;
    esac

    # Dimensions originales via sips.
    if ! dims=$(sips -g pixelWidth -g pixelHeight "$src" 2>/dev/null); then
        echo "Ignoré (lecture sips impossible) : $src" >&2
        failed=$((failed + 1))
        continue
    fi
    orig_w=$(awk '/pixelWidth:/  {print $2}' <<< "$dims")
    orig_h=$(awk '/pixelHeight:/ {print $2}' <<< "$dims")

    if ! is_non_negative_int "${orig_w:-x}" || ! is_non_negative_int "${orig_h:-x}"; then
        echo "Ignoré (dimensions illisibles) : $src" >&2
        failed=$((failed + 1))
        continue
    fi

    new_w=$(( orig_w - left - right ))
    new_h=$(( orig_h - top  - bottom ))

    if (( new_w <= 0 || new_h <= 0 )); then
        echo "Ignoré (rognage > taille de l'image ${orig_w}×${orig_h}) : $src" >&2
        skipped=$((skipped + 1))
        continue
    fi

    dir=$(dirname "$src")
    name=$(basename "$src")
    base="${name%.*}"
    ext=""
    [[ "$name" == *.* ]] && ext=".${name##*.}"

    dest="$dir/${base}_crop${ext}"
    n=1
    while [[ -e "$dest" ]]; do
        dest="$dir/${base}_crop-${n}${ext}"
        n=$((n + 1))
    done

    echo "→ $src  (${orig_w}×${orig_h} → ${new_w}×${new_h}, offset ${left},${top})"
    # sips --cropOffset Y X : origine en haut-à-gauche, en pixels.
    # --cropToHeightWidth H W : taille finale de la zone conservée.
    if sips \
        --cropOffset "$top" "$left" \
        --cropToHeightWidth "$new_h" "$new_w" \
        "$src" --out "$dest" >/dev/null; then
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

[[ "$failed" -eq 0 ]]
