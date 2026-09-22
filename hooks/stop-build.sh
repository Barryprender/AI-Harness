#!/bin/sh
# Stop: never let a turn end on a tree that does not verify. This one reports.
#
# WHY IT REPORTS AND DOES NOT BLOCK. A blocking end-of-turn hook can trap the
# agent in a loop, because the only way out of the block is the work the block
# is preventing. Worse, the operator never gets a turn to look. So this states
# what it found and hands the decision back: block where a claim becomes
# permanent, report where it is still soft. See commit-gate.sh for the other
# half of that rule.
#
# WHY IT DELEGATES. An earlier version of this ended at "does it compile", with
# one project's private trap hardcoded into a hook that ran everywhere. Two
# problems. Compiling is not verifying - a service can compile for months while
# a security claim in its README is enforced by no test at all. And a global
# hook cannot know each project's silent-skip condition, because every project
# has a different one: a database that is not listening here, a code generator
# that has not run there.
#
# So it asks the project. verify.sh is the definition of green, it is the same
# script CI runs, and there is one of it rather than two that drift.
#
# The contract is verify.sh --fast: the cheap tier, seconds not minutes. The
# expensive tier belongs in CI, not on the end of every turn.
#
# Contract: reads the Stop payload on stdin, writes hook JSON on stdout.
# Never exits non-zero - a broken gate must not break the session.

set -u

cat > /dev/null   # drain the payload

# Nothing changed this turn: nothing to check.
[ -n "$(git status --porcelain 2>/dev/null | head -1)" ] || exit 0

# JSON string escaping, one character at a time. The obvious version uses
# gsub, and the obvious version is wrong: a backslash in a gsub replacement is
# processed twice, so the escape for a quote came out as two backslashes and a
# quote and ended the JSON string early. Compiler output is full of quotes.
# Comparing characters against sprintf("%c", 92) has no such ambiguity.
esc() {
    tr -d '\000-\010\013-\037' | awk '
        BEGIN { bs = sprintf("%c", 92); q = sprintf("%c", 34) }
        {
            if (NR > 1) printf "%s", bs "n"
            out = ""
            for (i = 1; i <= length($0); i++) {
                c = substr($0, i, 1)
                if (c == bs)        out = out bs bs
                else if (c == q)    out = out bs q
                else if (c == "\t") out = out "    "
                else                out = out c
            }
            printf "%s", out
        }'
}

report() { # $1 = message
    printf '{"systemMessage":"%s"}\n' "$(printf '%s' "$1" | esc)"
    exit 0
}

# --- preferred path: the project's own definition of green --------------------

verify=""
if [ -f verify.sh ]; then
    verify=$(pwd)
else
    root=$(git rev-parse --show-toplevel 2>/dev/null)
    [ -n "$root" ] && [ -f "$root/verify.sh" ] && verify="$root"
fi

if [ -n "$verify" ]; then
    out=$(cd "$verify" && sh verify.sh --fast 2>&1)
    rc=$?
    [ "$rc" -eq 0 ] && exit 0

    # Report the collected failures, not the transcript of passes above them.
    detail=$(printf '%s' "$out" | sed -n '/FAILED:/,$p' | head -14)
    [ -n "$detail" ] || detail=$(printf '%s' "$out" | tail -14)

    if [ "$rc" -eq 1 ]; then
        report "./verify.sh --fast FAILED with uncommitted changes:

$detail"
    fi
    report "./verify.sh --fast could not complete (exit $rc). This is not a pass - a check did not run at all:

$detail"
fi

# --- fallback: no verify.sh here yet ------------------------------------------
#
# Deliberately thin. Give the project a verify.sh and this stops running.

[ -f go.mod ] || exit 0
command -v go >/dev/null 2>&1 || exit 0
git status --porcelain -- '*.go' 2>/dev/null | grep -q . || exit 0

if ! out=$(go build ./... 2>&1); then
    report "go build ./... FAILED with uncommitted Go changes (fallback check - this project has no verify.sh):

$(printf '%s' "$out" | head -12)"
fi

exit 0
