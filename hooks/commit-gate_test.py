"""Checks commit-gate.sh decides correctly.

    python hooks/commit-gate_test.py

It exists because the gate reads the command line, not just the index, and that
parsing is the part that can quietly go wrong. A gate that has stopped matching
fails open and says nothing, which looks exactly like approval. There is no
error to notice, so this file is the only thing that can tell the difference.
"""
import json
import os
import subprocess
import sys
import tempfile

GATE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "commit-gate.sh")

# Assembled from pieces so this file's own text cannot trip the gate when the
# harness inspects the command that runs it.
TRAILER = "Co-" + "Authored-By"
GENERATED = "Generated " + "with"
COMMIT = "git " + "commit"
ADD = "git " + "add"


def decide(command, cwd=None):
    payload = json.dumps({"tool_input": {"command": command}})
    out = subprocess.run(
        ["sh", GATE], input=payload, capture_output=True, text=True, timeout=60, cwd=cwd
    ).stdout.strip()
    if not out:
        return "silent"
    return json.loads(out)["hookSpecificOutput"]["permissionDecision"]


def commit_dash_a():
    """`commit -a` stages at commit time, so its count must come from the tree.

    That needs a tree with two modified files in it, which no other case has.
    """
    with tempfile.TemporaryDirectory() as d:
        def run(*a):
            subprocess.run(a, cwd=d, capture_output=True, timeout=30)

        run("git", "init", "-q")
        run("git", "config", "user.email", "t@t.t")
        run("git", "config", "user.name", "t")
        for name in ("a.txt", "b.txt"):
            with open(os.path.join(d, name), "w") as f:
                f.write("one")
        run("git", "add", ".")
        run("git", "commit", "-qm", "seed")
        for name in ("a.txt", "b.txt"):
            with open(os.path.join(d, name), "w") as f:
                f.write("two")
        return decide(COMMIT + ' -am "x"', cwd=d)


CASES = [
    # description, command (or a callable that produces the decision), expected
    ("two files staged in one command",
     ADD + ' a.go b.go && ' + COMMIT + ' -m "x"', "ask"),
    ("one file staged in one command",
     ADD + ' a.go && ' + COMMIT + ' -m "x"', "silent"),
    ("bare commit, nothing staged",
     COMMIT + ' -m "x"', "silent"),
    ("trailer in the message",
     COMMIT + ' -m "x\n\n' + TRAILER + ': A <a@b.c>"', "deny"),
    ("generated-with line in the message",
     COMMIT + ' -m "x\n\n' + GENERATED + ' a robot"', "deny"),
    ("prose naming both, no commit call",
     'echo "how to ' + COMMIT + ' without a ' + TRAILER + ' line"', "silent"),
    ("semicolon separator, three files",
     ADD + ' a.go b.go c.go; ' + COMMIT + ' -m x', "ask"),
    ("quoted path containing a space",
     ADD + ' "my file.go" && ' + COMMIT + ' -m "x"', "silent"),
    ("two paths, one of them quoted",
     ADD + ' "my file.go" other.go && ' + COMMIT + ' -m "x"', "ask"),
    ("flags are not paths",
     ADD + ' -v a.go && ' + COMMIT + ' -m "x"', "silent"),
    ("paths after a -- separator",
     ADD + ' -- a.go b.go && ' + COMMIT + ' -m "x"', "ask"),
    ("nothing to do with git",
     'ls -la && echo done', "silent"),
    ("commit -a with two modified files",
     commit_dash_a, "ask"),
]

failed = 0
for description, command, expected in CASES:
    got = command() if callable(command) else decide(command)
    ok = got == expected
    failed += not ok
    print("%s  %s: expected %s, got %s"
          % ("PASS" if ok else "FAIL", description, expected, got))

print("\n%d/%d passed" % (len(CASES) - failed, len(CASES)))
sys.exit(1 if failed else 0)
