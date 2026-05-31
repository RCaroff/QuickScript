#!/usr/bin/env zsh
#
# Test zsh — vérifie que QuickScript exécute correctement les scripts
# .zsh, transmet les @param en argv, et expose les variables QS_CONTEXT_*.
#
# @param name=world  Prénom à saluer
#
emulate -L zsh
setopt err_exit no_unset pipe_fail

name="${1:-world}"

print -- "Hello, ${name}!  (zsh ${ZSH_VERSION})"
print -- "argv         : $*"
print -- "QS_FILE_PATH : ${QS_CONTEXT_FILE_PATH:-(unset)}"
print -- "QS_TARGET    : ${QS_CONTEXT_TARGET_PATH:-(unset)}"
