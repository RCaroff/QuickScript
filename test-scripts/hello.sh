#!/usr/bin/env bash
#
# bash test — checks that QuickScript correctly runs
# .sh / .bash, passes the @param values in argv, and exposes the
# QS_CONTEXT_* variables.
#
# @param name=world  Name to greet
#
set -euo pipefail

name="${1:-world}"

echo "Hello, ${name}!  (bash $BASH_VERSION)"
echo "argv         : $*"
echo "QS_FILE_PATH : ${QS_CONTEXT_FILE_PATH:-(unset)}"
echo "QS_TARGET    : ${QS_CONTEXT_TARGET_PATH:-(unset)}"
