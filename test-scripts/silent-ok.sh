#!/usr/bin/env bash
#
# Démontre l'exécution silencieuse : le script fait quelque chose puis sort en 0.
# QuickScript n'affiche rien (pas d'alerte, pas de terminal).
#
# @param target=~/Desktop/quickscript-touch  Chemin du fichier à toucher
#
set -euo pipefail

target="${1:?chemin manquant}"
# Expansion manuelle de ~ (passé en littéral par l'app)
target="${target/#\~/$HOME}"

touch "$target"
