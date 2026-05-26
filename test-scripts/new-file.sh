#!/usr/bin/env bash
#
# Démontre la saisie de paramètres via la convention @param.
# QuickScript affichera 3 text fields au clic, puis lancera ce script avec
# les valeurs passées en argument ($1, $2, $3).
#
# @param target_dir=~/Desktop   Dossier où créer le fichier
# @param filename=note.txt      Nom du fichier à créer
# @param content=Hello          Contenu initial du fichier
#
set -euo pipefail

target_dir="${1:?dossier cible manquant}"
filename="${2:?nom de fichier manquant}"
content="${3:-}"

# Expansion manuelle de ~ (passé en littéral par l'app)
target_dir="${target_dir/#\~/$HOME}"

if [[ ! -d "$target_dir" ]]; then
    echo "Le dossier n'existe pas : $target_dir" >&2
    exit 1
fi

dest="$target_dir/$filename"

if [[ -e "$dest" ]]; then
    echo "Le fichier existe déjà : $dest" >&2
    exit 1
fi

printf '%s\n' "$content" > "$dest"
echo "Créé : $dest"
