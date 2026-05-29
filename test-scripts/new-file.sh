#!/usr/bin/env bash
#
# Demonstrates @param input via the convention.
# QuickScript shows 3 text fields on click, then runs this script with
# the values passed as arguments ($1, $2, $3).
#
# @param target_dir=~/Desktop   Folder where the file will be created
# @param filename=note.txt      Name of the file to create
# @param content=Hello          Initial content
#
set -euo pipefail

target_dir="${1:?missing target directory}"
filename="${2:?missing file name}"
content="${3:-}"

# Manual expansion of ~ (passed as a literal by the app)
target_dir="${target_dir/#\~/$HOME}"

if [[ ! -d "$target_dir" ]]; then
    echo "Folder does not exist: $target_dir" >&2
    exit 1
fi

dest="$target_dir/$filename"

if [[ -e "$dest" ]]; then
    echo "File already exists: $dest" >&2
    exit 1
fi

printf '%s\n' "$content" > "$dest"
echo "Created: $dest"
