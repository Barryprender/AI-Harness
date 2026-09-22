#!/bin/sh
# One definition of green for a Go project.
#
# This is a template. Copy it to the root of a project, adjust the checks, and
# keep the contract: it is the contract the harness relies on, not the checks.
#
#   exit 0   everything ran and passed
#   exit 1   something ran and failed
#   exit 2   something could not run at all
#
#   --fast   the cheap tier only, seconds not minutes: the harness calls this
#            inside the edit loop and at the end of a turn
#   (none)   everything, including the slow checks: CI and the operator call
#            this
#
# Failures are collected and printed at the end, each on a line starting
# "FAILED:". The harness shows the operator everything from the first one
# onwards, so a real failure is never buried in a transcript of passes.
#
# Exit 2 exists because the alternative is a lie. A suite that skipped half of
# itself, a linter that is not installed, a database that is not listening:
# every one of those exits 0 in a naive script, and a green run that measured
# nothing is indistinguishable from a green run that measured everything.

set -u

fast=0
[ "${1:-}" = "--fast" ] && fast=1

tmp=$(mktemp -d 2>/dev/null || echo "./.verify.$$")
mkdir -p "$tmp" || exit 2
trap 'rm -rf "$tmp"' EXIT
notes="$tmp/notes"
: > "$notes"

failed=0
unrun=0

fail() {
    failed=1
    printf 'FAILED: %s\n' "$1" >> "$notes"
    [ -n "${2:-}" ] && printf '%s\n\n' "$2" >> "$notes"
}

cannot_run() {
    unrun=1
    printf 'FAILED: %s could not run - %s\n' "$1" "$2" >> "$notes"
}

finish() {
    if [ -s "$notes" ]; then
        echo
        cat "$notes"
    fi
    [ "$failed" -eq 1 ] && exit 1
    [ "$unrun" -eq 1 ] && exit 2
    echo "OK"
    exit 0
}

# --- the toolchain itself ----------------------------------------------------

if ! command -v go >/dev/null 2>&1; then
    cannot_run "every check" "go is not on PATH"
    finish
fi

# --- formatting --------------------------------------------------------------

echo "gofmt"
unformatted=$(gofmt -l . 2>&1)
if [ -n "$unformatted" ]; then
    fail "gofmt" "These files are not formatted. Run: gofmt -w .

$unformatted"
fi

# --- static analysis ---------------------------------------------------------

echo "go vet"
if ! out=$(go vet ./... 2>&1); then
    fail "go vet" "$out"
fi

# --- tests -------------------------------------------------------------------

echo "go test"
if [ "$fast" -eq 1 ]; then
    if ! out=$(go test -short ./... 2>&1); then
        fail "go test -short" "$out"
    fi
    finish
fi

# Full tier from here down.
#
# -v costs nothing here and buys the skip count below. A test that skips is not
# a test that passed, and the default output says "ok" for both.
if ! out=$(go test -count=1 -v ./... 2>&1); then
    fail "go test" "$(printf '%s' "$out" | grep -E '^(---|\s+---) FAIL|^FAIL' | head -20)"
fi

# grep -c already prints 0 when it matches nothing; it just exits 1 while doing
# it. Adding "|| echo 0" appends a second 0 and the test below then compares
# the string "0 0" against an integer.
skipped=$(printf '%s' "$out" | grep -c -- '--- SKIP')
if [ "${skipped:-0}" -gt 0 ]; then
    cannot_run "$skipped test(s)" "they skipped, usually a missing service or build tag - a skipped test has not passed"
    printf '%s\n\n' "$(printf '%s' "$out" | grep -- '--- SKIP' | head -10)" >> "$notes"
fi

# --- known vulnerabilities ---------------------------------------------------
#
# Slow and network-bound, so it is in the full tier only. Not installed is
# exit 2, never exit 0: "we did not look" and "we looked and it is clean" are
# different answers.

echo "govulncheck"
if command -v govulncheck >/dev/null 2>&1; then
    if ! out=$(govulncheck ./... 2>&1); then
        fail "govulncheck" "$(printf '%s' "$out" | head -30)"
    fi
else
    cannot_run "govulncheck" "not installed - go install golang.org/x/vuln/cmd/govulncheck@latest"
fi

finish
