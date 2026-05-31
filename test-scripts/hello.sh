#!/usr/bin/env bash
#
# Test bash — vérifie que QuickScript exécute correctement les scripts
# .sh / .bash, transmet les @param en argv, et expose les variables
# QS_CONTEXT_*.
#
# @param name=world  Prénom à saluer
#
set -euo pipefail

name="${1:-world}"

echo "Hello, ${name}!  (bash $BASH_VERSION)"
echo "argv         : $*"
echo "QS_FILE_PATH : ${QS_CONTEXT_FILE_PATH:-(unset)}"
echo "QS_TARGET    : ${QS_CONTEXT_TARGET_PATH:-(unset)}"
