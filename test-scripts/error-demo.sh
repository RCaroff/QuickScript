#!/usr/bin/env bash
#
# Demonstrates the error alert in QuickScript.
# Exits with an error code after writing to both stdout and stderr.
#
echo "A few lines on stdout..."
echo "Another line on stdout."
echo "Oops, something went wrong." >&2
echo "Stack trace (fake):" >&2
echo "  at line 42 in foo()" >&2
echo "  at line 17 in main()" >&2
exit 1
