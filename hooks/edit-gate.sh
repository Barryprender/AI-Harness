#!/bin/sh
# PostToolUse gate for edits, however they were made. This one blocks.
#
# WHAT IT DOES. After an edit, it finds the project's own verify.sh and runs
# the cheap tier of it. A failure blocks, with the failing output fed back so
# the agent can fix it before doing anything else.
#
# WHY IT DELEGATES. The harness has no opinion about what green means. A
# formatter, a linter, a test runner, a code generator that has to run first -
# all of that is the project's business and it changes per project. What the
# harness owns is the moment: after every edit, before anything is built on
# top of it. See HARNESS.md for the contract verify.sh has to meet.
#
# WHY IT BLOCKS. A formatting or static-analysis failure has a fixed, known
# repair, and the agent is the right one to make it. Blocking here is not the
# same decision as blocking at the end of a turn - see stop-build.sh, which
# reports for a reason.
#
# WHERE CHANGED FILES COME FROM. git status, never the tool payload. An
# earlier version of this gate matched the edit tools only. A careful,
# surgical, multi-line change is easier to make through a shell script than
# through an edit tool, so the most careful edits were exactly the ones
# bypassing the gate. Anything that infers what changed from the shape of the
# event will miss whatever it did not anticipate.
#
# Contract: reads the PostToolUse payload on stdin, writes hook JSON on stdout.
# Never exits non-zero - a broken gate must not break the session.

set -u

cat > /dev/null   # drain the payload; this gate deliberately does not read it

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -n "$root" ] || exit 0

tmp=$(mktemp -d 2>/dev/null || echo "/tmp/edit-gate.$$")
mkdir -p "$tmp" 2>/dev/null || exit 0
trap 'rm -rf "$tmp"' EXIT

# JSON string escaping, in awk rather than in an interpreter. Enough for tool
# output: backslash, quote, tab, and the control characters that would make the
# JSON invalid. Newlines become the two characters backslash-n.
#
# Keeping this gate free of python means it still works on a machine where
# python is missing or - see the note in commit-gate.sh - present but broken.
esc() {
    tr -d '\000-\010\013\014\016-\037' | awk '
        { gsub(/\\/, "\\\\\\\\"); gsub(/"/, "\\\\\""); gsub(/\t/, "    ")
          if (NR > 1) printf "\\n"
          printf "%s", $0 }'
}

# Both of these are called directly, never on the right of a pipe: the right
# side of a pipe is a subshell, and exiting there would let the caller carry on
# and print a second decision after the first.
block() { # $1 = one-line summary, $2 = detail
    printf '{"decision":"block","reason":"%s\\n\\n%s","systemMessage":"%s"}\n' \
        "$(printf '%s' "$1" | esc)" "$(printf '%s' "$2" | esc)" "$1"
}

report() { # $1 = message
    printf '{"systemMessage":"%s"}\n' "$(printf '%s' "$1" | esc)"
}

# --- what changed, and in this turn -------------------------------------------
#
# The two-minute window keeps this to the work just done, rather than to every
# file left dirty from an hour ago.

git status --porcelain 2>/dev/null | sed -e 's/^...//' -e 's/^.* -> //' > "$tmp/dirty"
: > "$tmp/files"
while IFS= read -r p; do
    [ -n "$p" ] || continue
    f="$root/$p"
    [ -f "$f" ] || continue
    if [ -n "$(find "$f" -newermt '-120 seconds' -print 2>/dev/null)" ]; then
        printf '%s\n' "$f" >> "$tmp/files"
    fi
done < "$tmp/dirty"

[ -s "$tmp/files" ] || exit 0

# --- the project's own definition of green ------------------------------------
#
# verify.sh is looked for beside each changed file and upwards from there, so a
# repository holding several projects gets the right one for the file that
# changed rather than the one at the top.

: > "$tmp/verifiers"
while IFS= read -r f; do
    d=$(dirname "$f")
    while [ -n "$d" ] && [ "$d" != "/" ] && [ "$d" != "." ]; do
        if [ -f "$d/verify.sh" ]; then
            printf '%s\n' "$d" >> "$tmp/verifiers"
            break
        fi
        [ "$d" = "$root" ] && break
        parent=$(dirname "$d")
        [ "$parent" = "$d" ] && break
        d="$parent"
    done
done < "$tmp/files"

if [ -s "$tmp/verifiers" ]; then
    sort -u "$tmp/verifiers" > "$tmp/verifiers.u"
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        out=$(cd "$d" && sh verify.sh --fast 2>&1)
        rc=$?
        [ "$rc" -eq 0 ] && continue

        detail=$(printf '%s' "$out" | sed -n '/FAILED:/,$p' | head -25)
        [ -n "$detail" ] || detail=$(printf '%s' "$out" | tail -25)

        # Exit 1 is a real failure with a known repair: block.
        #
        # Exit 2 is a check that could not run at all - a missing tool, a
        # service that is down. Blocking on that would trap the session in a
        # loop it cannot edit its way out of, so it is reported instead. It is
        # still never silent. Not blocking is not the same as passing.
        if [ "$rc" -eq 1 ]; then
            block "verify.sh --fast failed after an edit. Fix this before continuing." "$detail"
        else
            report "verify.sh --fast could not complete (exit $rc). Nothing here has passed - a check did not run:

$detail"
        fi
        exit 0
    done < "$tmp/verifiers.u"
    exit 0
fi

# --- fallback -----------------------------------------------------------------
#
# ONLY for a project that has no verify.sh yet. It is deliberately thin: the
# harness guessing at a project's checks is how two definitions of green come
# to exist, and two definitions of green drift until there is none. Give the
# project a verify.sh and this code stops running.

command -v go >/dev/null 2>&1 || exit 0
: > "$tmp/pkgs"
while IFS= read -r f; do
    case "$f" in
        *.go) ;;
        *) continue ;;
    esac
    # Generated files are rewritten by their generator; reporting on them names
    # problems nobody is going to fix in place.
    case "$f" in
        *_templ.go|*.pb.go|*_generated.go|*/vendor/*|*/node_modules/*) continue ;;
    esac
    [ -f "$f" ] || continue
    [ -n "$(gofmt -l "$f" 2>/dev/null)" ] && gofmt -w "$f" 2>/dev/null
    dirname "$f" >> "$tmp/pkgs"
done < "$tmp/files"

[ -s "$tmp/pkgs" ] || exit 0
sort -u "$tmp/pkgs" > "$tmp/pkgs.u"
while IFS= read -r d; do
    [ -n "$d" ] || continue
    if ! out=$(cd "$d" && go vet . 2>&1); then
        block "go vet failed on a package you just edited (fallback check - this project has no verify.sh)." \
            "$(printf '%s' "$out" | head -25)"
        exit 0
    fi
done < "$tmp/pkgs.u"

exit 0
