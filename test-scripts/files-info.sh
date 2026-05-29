#!/usr/bin/env bash
#
# Test script for the « Run with QuickScript… » Quick Action.
# Reads the paths of selected files from $QS_CONTEXT_FILE_PATH (one per line)
# and logs their info to ~/Desktop/quickscript-files.log.
#
set -euo pipefail

log="$HOME/Desktop/quickscript-files.log"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    if [[ -z "${QS_CONTEXT_FILE_PATH:-}" ]]; then
        echo "(no file received — QS_CONTEXT_FILE_PATH is empty)"
    else
        count=0
        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            count=$((count + 1))
            if [[ -e "$f" ]]; then
                size=$(stat -f%z "$f" 2>/dev/null || echo "?")
                kind=$([[ -d "$f" ]] && echo "folder" || echo "file")
                echo "  • [$kind, $size B] $f"
            else
                echo "  • [not found] $f"
            fi
        done <<< "$QS_CONTEXT_FILE_PATH"
        echo "  → $count file(s) received"
    fi
    echo ""
} >> "$log"

echo "Logged → $log"
