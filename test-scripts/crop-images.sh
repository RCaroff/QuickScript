#!/usr/bin/env bash
#
# Crops the edges of the images selected in the Finder, via QuickScript.
#
# Image source, in priority order:
#   1. @param path                    (filled in the QuickScript dialog)
#   2. $QS_CONTEXT_FILE_PATH          (Finder service « Run with
#                                      QuickScript… » on a selection;
#                                      one path per line)
#
# Parameters:
#   - left   : pixels to remove from the left edge
#   - right  : pixels to remove from the right edge
#   - top    : pixels to remove from the top edge
#   - bottom : pixels to remove from the bottom edge
#   - path   : explicit path to an image (empty = use
#              $QS_CONTEXT_FILE_PATH)
#
# At least one of the four crop values must be > 0. Empty values are
# treated as 0.
#
# Output:
#   Each image is duplicated next to the original with a `_crop` suffix
#   (e.g. `photo.jpg` → `photo_crop.jpg`). Originals are never modified.
#
# @param left=0  Pixels to crop on the left
# @param right=0  Pixels to crop on the right
# @param top=0  Pixels to crop at the top
# @param bottom=0  Pixels to crop at the bottom
# @param path  Image path (empty = Finder selection)
#
set -euo pipefail

left="${1:-0}"
right="${2:-0}"
top="${3:-0}"
bottom="${4:-0}"
path_param="${5:-}"

# --- Parameter validation --------------------------------------------------

# An empty value is allowed and treated as 0.
[[ -z "$left"   ]] && left=0
[[ -z "$right"  ]] && right=0
[[ -z "$top"    ]] && top=0
[[ -z "$bottom" ]] && bottom=0

is_non_negative_int() { [[ "$1" =~ ^[0-9]+$ ]]; }

for pair in "left:$left" "right:$right" "top:$top" "bottom:$bottom"; do
    name="${pair%%:*}"
    val="${pair##*:}"
    if ! is_non_negative_int "$val"; then
        echo "Error: $name must be an integer ≥ 0 (got « $val »)." >&2
        exit 1
    fi
done

if (( left + right + top + bottom == 0 )); then
    echo "Error: set at least one crop value > 0." >&2
    exit 1
fi

# --- Resolve the files to process ------------------------------------------

# If the user entered an explicit path in the dialog, use it (single image).
# Otherwise fall back to $QS_CONTEXT_FILE_PATH (multi-line).
if [[ -n "$path_param" ]]; then
    source_list="$path_param"
elif [[ -n "${QS_CONTEXT_FILE_PATH:-}" ]]; then
    source_list="$QS_CONTEXT_FILE_PATH"
else
    echo "Error: no image received." >&2
    echo "Select one or more images in the Finder and run the script via" >&2
    echo "« Run with QuickScript… », or fill in the path parameter in the" >&2
    echo "dialog." >&2
    exit 1
fi

# --- Processing ------------------------------------------------------------

processed=0
skipped=0
failed=0

while IFS= read -r src; do
    [[ -z "$src" ]] && continue

    # Expand ~ → $HOME for paths typed by hand.
    src="${src/#\~/$HOME}"

    if [[ ! -f "$src" ]]; then
        echo "Skipped (not found): $src" >&2
        skipped=$((skipped + 1))
        continue
    fi

    ext_lc=$(printf '%s' "${src##*.}" | tr '[:upper:]' '[:lower:]')
    case "$ext_lc" in
        jpg|jpeg|png|tif|tiff|gif|bmp|heic|heif|webp) ;;
        *)
            echo "Skipped (unsupported extension): $src" >&2
            skipped=$((skipped + 1))
            continue
            ;;
    esac

    # Original dimensions via sips.
    if ! dims=$(sips -g pixelWidth -g pixelHeight "$src" 2>/dev/null); then
        echo "Skipped (sips could not read it): $src" >&2
        failed=$((failed + 1))
        continue
    fi
    orig_w=$(awk '/pixelWidth:/  {print $2}' <<< "$dims")
    orig_h=$(awk '/pixelHeight:/ {print $2}' <<< "$dims")

    if ! is_non_negative_int "${orig_w:-x}" || ! is_non_negative_int "${orig_h:-x}"; then
        echo "Skipped (unreadable dimensions): $src" >&2
        failed=$((failed + 1))
        continue
    fi

    new_w=$(( orig_w - left - right ))
    new_h=$(( orig_h - top  - bottom ))

    if (( new_w <= 0 || new_h <= 0 )); then
        echo "Skipped (crop larger than image ${orig_w}×${orig_h}): $src" >&2
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
    # sips --cropOffset Y X: origin at top-left, in pixels.
    # --cropToHeightWidth H W: final size of the kept area.
    if sips \
        --cropOffset "$top" "$left" \
        --cropToHeightWidth "$new_h" "$new_w" \
        "$src" --out "$dest" >/dev/null; then
        echo "  ✓ $dest"
        processed=$((processed + 1))
    else
        echo "  ✗ sips failed" >&2
        failed=$((failed + 1))
    fi
done <<< "$source_list"

echo ""
echo "Processed: $processed"
[[ "$skipped" -gt 0 ]] && echo "Skipped:   $skipped"
[[ "$failed"  -gt 0 ]] && echo "Failed:    $failed"

# Non-zero exit if anything failed, so QuickScript shows the error alert in
# silent mode.
[[ "$failed" -eq 0 ]]
