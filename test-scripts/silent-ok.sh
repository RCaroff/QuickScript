#!/usr/bin/env bash
#
# Demonstrates fully silent execution: the script does something and exits 0.
# QuickScript shows nothing (no alert, no terminal).
#
# @param target=~/Desktop/quickscript-touch   Path of the file to touch
#
set -euo pipefail

target="${1:?missing path}"
# Manual expansion of ~ (passed as a literal by the app)
target="${target/#\~/$HOME}"

touch "$target"
