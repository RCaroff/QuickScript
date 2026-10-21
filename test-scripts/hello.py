#!/usr/bin/env python3
#
# Python test — checks that QuickScript correctly runs
# .py via python3, passes the @param values in argv, and exposes the
# QS_CONTEXT_* variables.
#
# @param name=world  Name to greet
#
import os
import sys

name = sys.argv[1] if len(sys.argv) > 1 else "world"

print(f"Hello, {name}!  (python {sys.version.split()[0]})")
print(f"argv         : {sys.argv[1:]}")
print(f"QS_FILE_PATH : {os.environ.get('QS_CONTEXT_FILE_PATH', '(unset)')}")
print(f"QS_TARGET    : {os.environ.get('QS_CONTEXT_TARGET_PATH', '(unset)')}")
