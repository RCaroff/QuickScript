#!/usr/bin/env bash
#
# Flattens the tree: recursively moves all files from subdirectories into
# the target folder, then (optionally) removes the empty subdirectories.
#
# Resolution of the target folder, in priority order:
#   1. @param target_dir         (entered in the QuickScript dialog)
#   2. $QS_CONTEXT_TARGET_PATH   (Quick Action « Run here »)
#   3. $QS_CONTEXT_FILE_PATH     (right-click on a single folder in Finder)
#
# A list of sensitive folders (/ /Users $HOME /Applications …) is rejected
# to prevent any accident.
#
# @param target_dir=              Target folder (leave empty to use $QS_CONTEXT_TARGET_PATH)
# @param on_conflict=rename       On conflict: rename / skip / overwrite
# @param remove_empty_dirs=yes    Remove empty subdirectories afterwards? (yes/no)
#
set -euo pipefail

target_param="${1:-}"
on_conflict="${2:-rename}"
remove_empty_dirs="${3:-yes}"

# Target folder resolution
target=""
if [[ -n "$target_param" ]]; then
    target="$target_param"
elif [[ -n "${QS_CONTEXT_TARGET_PATH:-}" ]]; then
    target="$QS_CONTEXT_TARGET_PATH"
elif [[ -n "${QS_CONTEXT_FILE_PATH:-}" ]]; then
    # Right-click on (one or more) items in Finder.
    # Only accept if a single folder is selected.
    file_count=$(printf '%s\n' "$QS_CONTEXT_FILE_PATH" | grep -c .)
    if [[ "$file_count" -eq 1 ]] && [[ -d "$QS_CONTEXT_FILE_PATH" ]]; then
        target="$QS_CONTEXT_FILE_PATH"
    else
        echo "Error: multiple selection or non-folder." >&2
        echo "Select a single folder, or right-click in empty space." >&2
        exit 1
    fi
else
    echo "Error: no target folder." >&2
    echo "Run the script from Finder (right-click on a folder or in empty space)," >&2
    echo "or fill in the target_dir parameter." >&2
    exit 1
fi

# Tilde expansion and absolute path resolution
target="${target/#\~/$HOME}"
if ! target=$(cd "$target" 2>/dev/null && pwd -P); then
    echo "Target folder not found: ${target_param:-$QS_CONTEXT_TARGET_PATH}" >&2
    exit 1
fi

# Safety guard: reject sensitive folders. Without it, running the script
# without context ($PWD=/ when the app is launched by macOS) would be a
# disaster.
forbidden=(
    "/"
    "/Users"
    "/Applications"
    "/System"
    "/Library"
    "/private"
    "/usr"
    "/etc"
    "/var"
    "/bin"
    "/sbin"
    "/opt"
    "$HOME"
)
for f in "${forbidden[@]}"; do
    if [[ "$target" == "$f" ]]; then
        echo "Refused: « $target » is a sensitive folder." >&2
        echo "Choose a specific working folder." >&2
        exit 2
    fi
done

echo "Target: $target"

moved=0
skipped=0
overwritten=0

# -mindepth 2: ignore files already at the root of $target
while IFS= read -r -d '' src; do
    name=$(basename "$src")
    dest="$target/$name"

    if [[ -e "$dest" ]]; then
        case "$on_conflict" in
            skip)
                echo "Already exists, skipped: $name" >&2
                skipped=$((skipped + 1))
                continue
                ;;
            overwrite)
                mv -f "$src" "$dest"
                overwritten=$((overwritten + 1))
                ;;
            rename|*)
                base="${name%.*}"
                ext=""
                [[ "$name" == *.* && "$name" != .* ]] && ext=".${name##*.}"
                n=1
                while [[ -e "$target/${base}-${n}${ext}" ]]; do
                    n=$((n + 1))
                done
                mv "$src" "$target/${base}-${n}${ext}"
                moved=$((moved + 1))
                ;;
        esac
    else
        mv "$src" "$dest"
        moved=$((moved + 1))
    fi
done < <(find "$target" -mindepth 2 -type f -print0)

if [[ "$remove_empty_dirs" == "yes" ]]; then
    find "$target" -mindepth 1 -type d -empty -delete 2>/dev/null || true
fi

echo "Moved       : $moved"
[[ "$on_conflict" == "overwrite" ]] && echo "Overwritten : $overwritten"
[[ "$on_conflict" == "skip" ]] && echo "Skipped     : $skipped"
