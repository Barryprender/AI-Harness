# 2. Treat the harness as advisory, and keep authority on the remote

Status: accepted, 2026-09-22

## Context

The gates are convincing. They deny commits, they block edits, they print
refusals in the imperative. It is a short step from there to treating them as a
control - to saying that a commit which reached the remote must have been
verified, because the gate would have stopped it otherwise.

That is false, and it is worth writing down why, because the mistake is
attractive rather than careless.

Every gate is a plain file. `commit-gate.sh` is a shell script with no
signature, no checksum and nothing watching it. Anyone who can write to it can
replace its contents with `exit 0`, and the result is a harness that approves
everything and reports nothing - which is the exact failure mode the rest of
this repository is built to make visible. Nobody would notice. There would be
no error.

The situation is worse than a gate that merely fails open. A hook is a standing
instruction to run a script on every edit the developer makes. Somebody who
gains write access to the hooks has been handed persistence, with the target's
own tooling to carry it.

There is a related path that does not need a compromised machine at all. An
agent reads repository content, and repository content is untrusted input. A
file in a dependency, an issue template, a comment in generated code - any of
them can contain a sentence addressed to the agent rather than to a human.

## Decision

The harness is a quality instrument. It is not a security boundary, and no
document here will claim otherwise.

Concretely:

- A local gate is **advisory**. It assumes the machine it runs on is trusted,
  because it has no way to check.
- Authority lives where the compromised machine cannot reach: a protected
  branch, required status checks running `verify.sh` on a clean runner, review
  by a second person, and commits signed by a hardware key that will not sign
  without a physical touch.
- The hooks stay in a repository of their own, separate from any project being
  worked on, so that a change to a gate appears in its own `git status` rather
  than buried in a large diff.
- `SECURITY.md` states what the harness does not defend against, in the same
  detail as what it does.

## Consequences

The repository is now on record saying its own central mechanism can be turned
off by anyone with write access. That reads like a weakness in a README. It is
the opposite: a verification tool that will not state its own limits is asking
to be trusted in the one situation where trusting it is wrong.

Nothing in the harness enforces any of the remote-side controls above. They are
settings in a forge and a key in somebody's pocket, and this repository cannot
check them. Saying so is the point of the record.

The separate-repository rule costs something real. Wiring the hooks means an
absolute path in a settings file, which is more friction than dropping them
into the project being worked on. The friction is accepted.

## Follow-up

If a gate is ever given a job where being bypassed would be a security
incident rather than a quality problem, that job is in the wrong place. Move it
to CI, where the developer's machine is not the thing running it.
