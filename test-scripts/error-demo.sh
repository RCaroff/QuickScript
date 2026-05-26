#!/usr/bin/env bash
#
# Démontre l'alerte d'erreur de QuickScript.
# Sort en erreur après avoir écrit quelque chose sur stdout et stderr.
#
echo "Quelques lignes sur stdout..."
echo "Encore une autre ligne sur stdout."
echo "Oups, quelque chose s'est mal passé." >&2
echo "Stack trace (factice) :" >&2
echo "  at line 42 in foo()" >&2
echo "  at line 17 in main()" >&2
exit 1
