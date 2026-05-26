#!/usr/bin/env bash
#
# Script de test pour la Quick Action « Exécuter avec QuickScript… ».
# Lit les chemins des fichiers sélectionnés depuis $QS_CONTEXT_FILE_PATH
# (un par ligne) et log leurs infos sur ~/Desktop/quickscript-files.log.
#
set -euo pipefail

log="$HOME/Desktop/quickscript-files.log"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    if [[ -z "${QS_CONTEXT_FILE_PATH:-}" ]]; then
        echo "(aucun fichier reçu — variable QS_CONTEXT_FILE_PATH vide)"
    else
        count=0
        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            count=$((count + 1))
            if [[ -e "$f" ]]; then
                size=$(stat -f%z "$f" 2>/dev/null || echo "?")
                kind=$([[ -d "$f" ]] && echo "dossier" || echo "fichier")
                echo "  • [$kind, $size B] $f"
            else
                echo "  • [introuvable] $f"
            fi
        done <<< "$QS_CONTEXT_FILE_PATH"
        echo "  → $count fichier(s) reçu(s)"
    fi
    echo ""
} >> "$log"

echo "Logged → $log"
