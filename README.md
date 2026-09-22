# claude-harness

This repository does not make an AI agent write correct code. It makes it hard
to ship code that has not been verified first.

It is a working extraction of the governance harness I run over my own
AI-assisted development: four hooks, one contract, and a small Go service for
the hooks to actually govern, so you can clone it and watch a gate block a bad
commit rather than take my word for it.

```sh
git clone <this repo> && cd claude-harness
sh hooks/edit-gate_test.sh
sh hooks/stop-build_test.sh
sh hooks/charter-check_test.sh
python hooks/commit-gate_test.py
```

---

## The argument

Six positions. Each one is a decision that cost something to get wrong.

### 1. Block or report is a risk decision, not a setting

Blocking is not a measure of how much a check matters. It is a measure of how
reversible the moment is.

A commit is where a claim stops being provisional. Once it is pushed it is in
other people's clones and its message is read by people who were not there.
That is worth blocking. A half-finished edit is not: the agent is still
working, and the repair is known and bounded, so blocking there is cheap and
useful.

The end of a turn is the subtle one. A **blocking** end-of-turn hook can trap
the agent in a loop, because the only thing that would satisfy the block is the
work the block is preventing — and the operator never gets a turn to look. So
`stop-build.sh` reports and hands the decision back.

Recorded as [ADR 0001](docs/adr/0001-block-where-a-claim-becomes-permanent.md).

### 2. A gate must never crash the session

Every hook here exits `0`, always, whatever it found. The decision travels in
the JSON it prints, never in its own exit status.

A guardrail that crashes takes down the workflow it was guarding, and the first
thing anyone does with a guardrail that breaks their workflow is remove it. The
tests assert this directly: *the gate itself exits 0 while blocking*.

### 3. Three exit codes, not two

```
0   every check ran and passed
1   a check ran and failed
2   a check could not run at all
```

Collapsing `2` into `0` is the single easiest way for a verification system to
lie to you, and it lies silently. A suite that skipped half of itself because a
database was not listening prints `ok` and exits `0`. A vulnerability scanner
that is not installed finds no vulnerabilities.

The example project carries a test that skips without `HARNESS_EXAMPLE_E2E=1`,
so you can see the difference for yourself:

```
FAILED: 1 test(s) could not run - they skipped, usually a missing service or
build tag - a skipped test has not passed
--- SKIP: TestHealthEndToEnd (0.00s)
```

`go test ./...` calls that run green.

### 4. Change detection comes from `git status`, not the tool payload

An earlier version of the edit gate matched the edit tools only. A careful,
surgical, multi-line change is easier to make through a shell script than
through an edit tool — so the most careful edits were exactly the ones
bypassing the gate.

Anything that infers *what changed* from the shape of the event will miss
whatever it did not anticipate. `git status` already knows. `edit-gate.sh`
drains its payload and reads nothing out of it, on purpose.

### 5. Gates are tested

A gate that has silently stopped matching produces no output, blocks nothing,
and looks exactly like approval. There is no error. Nothing in a normal session
would ever tell you.

Each gate here has a test beside it, and CI runs all four. This is not a
theoretical risk — writing this repository, the edit gate's JSON escaping was
wrong in a way that made every real failure unparseable, and the test that was
supposed to catch it was passing against input that had been mangled before it
arrived. Both are fixed; both are in the git history.

### 6. Disclosure lives in prose, not in commit metadata

No `Co-Authored-By`, no `Generated with`, on any commit. `commit-gate.sh`
denies them outright, and this repository's own history has none.

A trailer is a claim about authorship pushed into a field nobody reads, in a
place it cannot be qualified. A paragraph is a disclosure a person stands
behind. The agent writes code; the operator reviews it, commits it, and is
accountable for it. Authorship follows accountability, not keystrokes.

Which is why the disclosure for this repository is a sentence rather than a
trailer: **the code here was written with an AI coding agent, under the harness
it contains, and I read every line of it before it was committed.**

---

## Watch it work

Break the example service on purpose. The gate reads the tree, finds
`example/verify.sh`, runs its fast tier, and blocks with the failure fed back.

**Bad formatting:**

```
decision: block

verify.sh --fast failed after an edit. Fix this before continuing.

FAILED: gofmt
These files are not formatted. Run: gofmt -w .

main.go
```

**A behaviour change that breaks a test:**

```
decision: block

verify.sh --fast failed after an edit. Fix this before continuing.

FAILED: go test -short
--- FAIL: TestHealthReportsOK (0.00s)
    main_test.go:17: body = "{\"status\":\"fine\"}\n", want "{\"status\":\"ok\"}\n"
FAIL
FAIL    harness/example    1.874s
```

**An attribution trailer on a commit:**

```
decision: deny

This commit carries an attribution trailer. CLAUDE.md forbids it in the
imperative: never add a Co-Authored-By line or any other attribution line.
The operator is the author of the commit; disclosure of AI assistance belongs
in prose that a human stands behind, not in commit metadata. Remove the
trailer and commit again.
```

**A toolchain nobody has updated** (the full tier, not the fast one):

```
FAILED: govulncheck

Vulnerability #1: GO-2026-6090
    Limit handshake messages we are willing to accept post-handshake in
    crypto/tls
  Standard library
    Found in: crypto/tls@go1.25.6
    Fixed in: crypto/tls@go1.25.13
```

That last one is not a staged example. It is what the full tier reported on the
machine this repository was written on, against a service whose only import is
the standard library.

To reproduce them yourself:

```sh
cd example
sh verify.sh --fast          # the tier the harness calls: seconds
sh verify.sh                 # everything, including the vulnerability scan
printf '%s\n' 'func x()  int {' >> main.go && cd .. && printf '{}' | sh hooks/edit-gate.sh
git checkout -- example/main.go
```

---

## What is here

```
CLAUDE.md                   the constitution: authorship, the ladder before
                            writing code, skipping is not passing
HARNESS.md                  the contract - what verify.sh must guarantee, and
                            what the harness guarantees in return
hooks/
  edit-gate.sh              after an edit: runs verify.sh --fast, blocks
  commit-gate.sh            before a commit: denies attribution trailers,
                            asks about multi-file staging
  stop-build.sh             end of turn: runs verify.sh --fast, reports
  charter-check.sh          session start: names missing standing artifacts
  *_test.sh, *_test.py      one test per gate
templates/go/verify.sh      a working verify.sh: gofmt, go vet, go test,
                            skip detection, govulncheck, exits 0/1/2
example/                    a stub HTTP service for the harness to govern
settings.example.json       how the four hooks are wired up
docs/adr/                   decisions that would otherwise be reconstructed
                            from the code
```

### The contract, in one paragraph

The harness decides **when** to check and **what happens** when a check fails.
The project decides **what green means** for itself, in one executable
`verify.sh` in its root — the same script CI runs, so there is one definition
of green and not two that drift. Neither side adapts to the other, and the
harness never looks inside. A project in any language is governable as long as
its `verify.sh` exits 0, 1 or 2 honestly and has a cheap `--fast` tier.

Full contract in [HARNESS.md](HARNESS.md).

### Wiring it up

`settings.example.json` shows the four hooks configured for Claude Code. Copy
the `hooks` block into `~/.claude/settings.json` and fix the paths.

Read the scripts before you do that. They are short, and a hook you have not
read is a program you have given a shell on every edit you make. See
[SECURITY.md](SECURITY.md) for what they touch.

---

## Not built yet

Stated plainly, because overclaiming here costs more than it earns.

- **Multi-language support is a contract, not an implementation.** The gates
  are language-agnostic and the delegation works, but the only `verify.sh`
  template in this repository is the Go one. A TypeScript or Python project
  would write its own today.
- **There is no stack auto-detection.** A project either has a `verify.sh` or
  it gets the thin fallback path, which is Go-only and deliberately minimal.
  Automatically working out what a project is remains a proposal.
- **The fallback paths are not the point.** They exist so a project without a
  `verify.sh` is not completely ungoverned. They are worse than a `verify.sh`
  in every case and they are meant to be deleted by adoption.
- **`charter-check.sh` probes for existence, not for content.** It can tell
  you there is no `SECURITY.md`. It cannot tell you the one you have is true.
- **This is extracted from a private configuration, generalized.** The
  mechanism is what ran; the specific checks in the original were tied to
  projects that are not mine to publish.

---

## Licence

[MIT](LICENSE).
