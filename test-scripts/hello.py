#!/usr/bin/env python3
#
# Test Python — vérifie que QuickScript exécute correctement les scripts
# .py via python3, transmet les @param en argv, et expose les variables
# QS_CONTEXT_*.
#
# @param name=world  Prénom à saluer
#
import os
import sys

name = sys.argv[1] if len(sys.argv) > 1 else "world"

print(f"Hello, {name}!  (python {sys.version.split()[0]})")
print(f"argv         : {sys.argv[1:]}")
print(f"QS_FILE_PATH : {os.environ.get('QS_CONTEXT_FILE_PATH', '(unset)')}")
print(f"QS_TARGET    : {os.environ.get('QS_CONTEXT_TARGET_PATH', '(unset)')}")
