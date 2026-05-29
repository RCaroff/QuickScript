#!/usr/bin/env bash
#
# Demonstrates stdin prompts captured at runtime by QuickScript.
# No @param directive here: the script asks for everything at execution.
#
set -euo pipefail

read -rp "What's your name? " name
read -rp "How old are you? " age
read -rp "Confirm? (y/n) " confirm

if [[ "$confirm" != "y" ]]; then
    echo "Cancelled by user." >&2
    exit 2
fi

echo "Hello $name, you are $age years old."
