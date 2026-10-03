#!/usr/bin/env bash
# Minimal assertion helpers for bash tests. Source this file, call finish at the end.
TESTS_RUN=0
TESTS_FAILED=0
_ok() { TESTS_RUN=$((TESTS_RUN + 1)); }
_ko() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1"; }
assert_eq() { if [ "$1" = "$2" ]; then _ok; else _ko "$3 (expected [$1], got [$2])"; fi; }
assert_contains() { case "$1" in *"$2"*) _ok ;; *) _ko "$3 (missing [$2])"; echo "--- output was:"; echo "$1"; echo "---" ;; esac; }
assert_not_contains() { case "$1" in *"$2"*) _ko "$3 (unexpected [$2])" ;; *) _ok ;; esac; }
assert_file() { if [ -f "$1" ]; then _ok; else _ko "$2 (no file: $1)"; fi; }
finish() { echo "$TESTS_RUN checks, $TESTS_FAILED failed"; [ "$TESTS_FAILED" -eq 0 ]; }
