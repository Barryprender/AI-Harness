# 1. Block where a claim becomes permanent, report where it is still soft

Status: accepted, 2026-09-22

## Context

Four gates run at four different moments: after an edit, before a commit, at
the end of a turn, and at the start of a session. Each one has to decide what
to do when it finds a problem. The obvious answer is that a check either
matters or it does not, so all four should block.

That answer is wrong, and it is wrong in a way that only shows up in use.

A blocking end-of-turn hook has no exit. The agent finishes a turn, the hook
refuses it, the agent tries again, the hook refuses again. The only thing that
would satisfy the hook is the work the block is preventing it from getting to,
and the operator never gets a turn to look at what is happening. A gate that
can loop is worse than no gate, because it will be switched off and take the
non-looping gates with it.

A blocking edit gate has an exit: fix the formatting, fix the vet error, edit
again. The repair is known, bounded, and the agent is the one who can make it.

A commit is different from both. It is the point at which a claim stops being
provisional. Once it is pushed it is in other people's clones and in their
review tools, and the message on it will be read by people who were not here.

## Decision

The decision to block follows from how reversible the moment is, not from how
important the check is.

| Gate | Moment | Reversible? | Acts |
|------|--------|-------------|------|
| `edit-gate.sh` | after an edit | yes, trivially | blocks |
| `commit-gate.sh` | before a commit | no, once pushed | blocks |
| `stop-build.sh` | end of turn | yes, but blocking loops | reports |
| `charter-check.sh` | session start | nothing has happened yet | reports |

A second rule falls out of the same reasoning. Exit code 2 from `verify.sh` -
a check that could not run at all - never blocks anywhere, because no amount of
editing code will install a missing tool. It is always reported and never
silent.

## Consequences

The end of a turn can now pass with a failing tree. That is accepted: the
report says so plainly, and the operator decides whether it is worth another
turn. The alternative was a loop.

Two gates that look similar behave differently, which is a thing somebody will
try to "fix" later. `stop-build_test.sh` asserts that the end-of-turn hook does
not block, so that change fails a test rather than shipping.

## Follow-up

If the edit gate is ever observed looping - blocking on something the agent
cannot repair by editing - it moves to reporting and this record is superseded.
