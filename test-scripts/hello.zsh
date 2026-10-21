#!/usr/bin/env zsh
#
# zsh test — checks that QuickScript correctly runs
# .zsh, passes the @param values in argv, and exposes the QS_CONTEXT_*
# variables.
#
# @param name=world  Name to greet
#
emulate -L zsh
setopt err_exit no_unset pipe_fail

name="${1:-world}"

print -- "Hello, ${name}!  (zsh ${ZSH_VERSION})"
print -- "argv         : $*"
print -- "QS_FILE_PATH : ${QS_CONTEXT_FILE_PATH:-(unset)}"
print -- "QS_TARGET    : ${QS_CONTEXT_TARGET_PATH:-(unset)}"
