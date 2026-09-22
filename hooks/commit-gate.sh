#!/bin/sh
# PreToolUse gate for git commits. This one blocks.
#
# A commit is the moment a claim stops being provisional. Once it is pushed it
# cannot be taken back, and its message will be read by people who were not
# here. That is why this gate blocks and the end-of-turn gate does not.
#
# It enforces two conventions from CLAUDE.md:
#
#   1. No attribution trailer. Hard deny. The rule is absolute, so the gate is.
#   2. One commit per file. Ask, not deny - there are legitimate exceptions
#      (a rename, a generated file that must move with its source) and the
#      operator, not this script, decides which those are.
#
# The file count comes from the command line as well as the index. Asking git
# what is staged is only correct once staging has happened: `git add a b c &&
# git commit` runs this hook before the add, so the index is empty and the
# check passes silently on exactly the commits it exists to catch. `git commit
# -a` has the same hole from the other direction - it stages at commit time,
# after this hook has already looked.
#
# Contract: reads the PreToolUse payload on stdin, writes hook JSON on stdout.
# Never exits non-zero - a broken gate must not break the session.

set -u

payload=$(cat)

# Cheap prefilter. Nearly every command this hook sees has nothing to do with
# git, and there is no reason to start an interpreter for those.
case "$payload" in
    *"git commit"*|*"git"*"commit"*) ;;
    *) exit 0 ;;
esac

emit() { # $1 = deny|ask, $2 = reason
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' "$1" "$2"
    exit 0
}

# Probed by running it, not by looking for it on PATH. On Windows, python3 is
# often an App Execution Alias that exists, resolves, and then refuses to run -
# `command -v` says yes and the interpreter produces nothing. That is the same
# class of bug this whole harness is about: present is not the same as working.
PY=""
for c in python3 python py; do
    if command -v "$c" >/dev/null 2>&1 && "$c" -c "" >/dev/null 2>&1; then
        PY="$c"
        break
    fi
done

# Could not run is not passed. At a blocking point that means asking the
# operator, not waving it through and not crashing the session.
[ -n "$PY" ] || emit ask "The commit gate could not run: no python interpreter is on PATH, so the commit message and the staged file count were never inspected. This is not an approval. Check the message for an attribution trailer and confirm the staging is deliberate before you continue."

# Both helper programs below are held in quoted heredocs, and the quoted
# delimiter is the point of them.
#
# Passing a program as `python -c "..."` puts it inside a double-quoted shell
# string, where $, backslash and backticks still belong to the shell. A pair of
# backticks in a *Python comment* was being run as a command substitution
# before Python ever saw the file. It was harmless by luck. A quoted heredoc
# hands the text over untouched, which is the only version of this that is
# correct rather than lucky.

# The command, but only from the point where it actually invokes a commit.
#
# Matching the bare phrase anywhere in the text is too loose: a script that
# writes documentation *about* commit conventions contains both the words and
# no commit at all, and this gate denied exactly that the first time it ran. An
# invocation is the phrase at the start of the command or straight after a
# separator, and only what follows it is the commit.
find_commit=$(cat <<'PYPROG'
import sys, json, re
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
raw = (d.get('tool_input') or {}).get('command') or ''
m = re.search(r'(?:^|[;&|]\s*|\n\s*)git\s+commit\b', raw)
if not m:
    sys.exit(0)
print(raw[m.start():].replace(chr(10), ' '))
PYPROG
)

cmd=$(printf '%s' "$payload" | "$PY" -c "$find_commit" 2>/dev/null)

[ -n "$cmd" ] || exit 0

case "$cmd" in
    *Co-Authored-By*|*Co-authored-by*|*co-authored-by*|*"Generated with"*)
        emit deny "This commit carries an attribution trailer. CLAUDE.md forbids it in the imperative: never add a Co-Authored-By line or any other attribution line. The operator is the author of the commit; disclosure of AI assistance belongs in prose that a human stands behind, not in commit metadata. Remove the trailer and commit again."
        ;;
esac

# How many distinct paths this commit would touch: what is staged now, plus what
# the same command line is about to stage. Counting the union rather than adding
# the two keeps a file named in both from being counted twice.
count_paths=$(cat <<'PYPROG'
import json, re, shlex, subprocess, sys

def git(*args):
    try:
        out = subprocess.run(('git',) + args, capture_output=True, text=True, timeout=10)
    except Exception:
        return []
    return [l for l in out.stdout.splitlines() if l.strip()]

try:
    raw = (json.load(sys.stdin).get('tool_input') or {}).get('command') or ''
except Exception:
    print(0); sys.exit(0)

paths = set(git('diff', '--cached', '--name-only'))

# Split the command line into its separate invocations. punctuation_chars makes
# shlex hand back ';', '&&', '||' and friends as tokens of their own, so quoted
# arguments survive and a heredoc body simply fails to look like a git call.
try:
    lex = shlex.shlex(raw, posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    tokens = list(lex)
except Exception:
    tokens = []

cmds, cur = [], []
for t in tokens:
    if t and all(c in ';&|()<>' for c in t):
        cmds.append(cur); cur = []
    else:
        cur.append(t)
cmds.append(cur)

# -A, -u and . stage whatever the tree happens to hold, and so does commit -a.
# The count then has to come from the tree, not from the argument list.
EVERYTHING = {'.', '-A', '--all', '-u', '--update', ':/', '*'}

for c in cmds:
    if len(c) < 2 or c[0] != 'git':
        continue
    if c[1] == 'add':
        args, seen_ddash = c[2:], False
        for a in args:
            if a == '--':
                seen_ddash = True
                continue
            if a in EVERYTHING:
                paths.update(git('status', '--porcelain', '--untracked-files=all'))
            elif seen_ddash or not a.startswith('-'):
                paths.add(a)
    elif c[1] == 'commit':
        for a in c[2:]:
            if a == '--all' or (re.match(r'^-[A-Za-z]+$', a) and 'a' in a[1:]):
                paths.update(git('diff', '--name-only'))
                break

print(len(paths))
PYPROG
)

staged=$(printf '%s' "$payload" | "$PY" -c "$count_paths" 2>/dev/null)

if [ "${staged:-0}" -gt 1 ]; then
    emit ask "$staged files are staged for one commit. The convention here is one commit per file, ordered so the history builds up sensibly and each commit can be read on its own. Confirm if this is a deliberate exception (a rename, or a file that cannot stand alone); otherwise stage and commit them one at a time."
fi

exit 0
