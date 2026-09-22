#!/bin/sh
# This project's definition of green.
#
# It is the Go template, unmodified. A project with anything unusual about it —
# a database the suite needs, a code generator that must run first, a coverage
# floor — copies the template instead of delegating to it and edits its own
# copy. The harness does not care which, as long as the contract in HARNESS.md
# holds: 0 passed, 1 failed, 2 could not run, and --fast is cheap.

set -u
exec sh "$(dirname "$0")/../templates/go/verify.sh" "$@"
