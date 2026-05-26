#!/usr/bin/env bash
#
# Démontre les prompts stdin captés au runtime par QuickScript.
# Aucune directive @param ici : le script demande tout à l'exécution.
#
set -euo pipefail

read -rp "Comment t'appelles-tu ? " name
read -rp "Quel âge as-tu ? " age
read -rp "Confirmer ? (o/n) " confirm

if [[ "$confirm" != "o" ]]; then
    echo "Annulé par l'utilisateur." >&2
    exit 2
fi

echo "Bonjour $name, tu as $age ans."
