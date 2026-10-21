#!/usr/bin/env bash
#
# Resizes the images selected in the Finder, via QuickScript.
#
# Image source, in priority order:
#   1. @param path                    (filled in the QuickScript dialog)
#   2. $QS_CONTEXT_FILE_PATH          (Finder service « Run with
#                                      QuickScript… » on a selection;
#                                      one path per line)
#
# Parameters:
#   - width  : target width in pixels  (leave empty to keep the aspect ratio)
#   - height : target height in pixels (leave empty to keep the aspect ratio)
#   - path   : explicit path to an image (empty = use
#              $QS_CONTEXT_FILE_PATH)
#
# At least one of the two must be set. If only one is given, sips keeps the
# aspect ratio and computes the other side.
#
# Output:
#   Each image is duplicated next to the original with a `_WxH` suffix
#   (e.g. `photo.jpg` → `photo_800x600.jpg`). Originals are never modified.
#
# @param width  Target width in pixels (empty = keep ratio)
# @param height  Target height in pixels (empty = keep ratio)
# @param path  Image path (empty = Finder selection)
#
set -euo pipefail

width="${1:-}"
height="${2:-}"
path_param="${3:-}"

# --- Parameter validation --------------------------------------------------

if [[ -z "$width" && -z "$height" ]]; then
    echo "Error: set at least width or height." >&2
    exit 1
fi

is_positive_int() { [[ "$1" =~ ^[0-9]+$ && "$1" -gt 0 ]]; }

if [[ -n "$width" ]] && ! is_positive_int "$width"; then
    echo "Error: width must be a positive integer (got « $width »)." >&2
    exit 1
fi
if [[ -n "$height" ]] && ! is_positive_int "$height"; then
    echo "Error: height must be a positive integer (got « $height »)." >&2
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

# Output suffix: `_WxH`, `_Wx` or `_xH` depending on what was given.
suffix="_${width}x${height}"

# --- Build the sips arguments ----------------------------------------------

sips_args=()
if [[ -n "$width" && -n "$height" ]]; then
    # `--resampleHeightWidth`: note the H W order (sips legacy).
    sips_args=(--resampleHeightWidth "$height" "$width")
elif [[ -n "$width" ]]; then
    sips_args=(--resampleWidth "$width")
else
    sips_args=(--resampleHeight "$height")
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

    # Quick extension filter to avoid running sips on text files.
    # sips supports jpg/jpeg/png/tiff/gif/bmp/heic/webp.
    ext_lc=$(printf '%s' "${src##*.}" | tr '[:upper:]' '[:lower:]')
    case "$ext_lc" in
        jpg|jpeg|png|tif|tiff|gif|bmp|heic|heif|webp) ;;
        *)
            echo "Skipped (unsupported extension): $src" >&2
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

    # Avoid collisions: if the target already exists, add a counter.
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
