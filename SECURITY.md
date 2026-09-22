# Security

## What this repository is

Four shell scripts that run as editor hooks, a shell template, and a stub Go
service that exists so the scripts have something to act on. It is a
demonstration. Nothing here is a service, and nothing here should be exposed to
a network.

## Threat model

### What the harness defends against

Mistakes, drift, and unverified claims. An agent or a person shipping something
nobody checked. A check that quietly stopped working months ago and has been
reporting approval ever since - which is what the tests beside each gate are
for.

All of those are honest failures. Nobody is trying.

### What it does not defend against

Anyone who can write to `hooks/*.sh`, to a project's `verify.sh`, or to the
settings file that wires them up.

These are plain files with no integrity checking of any kind. A gate edited to
`exit 0` approves everything and says nothing about it - which is precisely the
failure this repository exists to make visible. The harness cannot detect that,
because the harness is the thing being edited.

It is worse than passive. **A hook is a standing instruction to run a script on
every edit.** Handed to an attacker, that is a persistence mechanism with the
target's own tooling behind it.

So: **the harness is not a security boundary, and must never be counted as
one.** It is a quality instrument. It assumes the machine it runs on is
trusted, because it has no way to check.

### Where the authority actually lives

A gate the attacker controls is advisory. Only a gate they cannot reach from
the compromised machine is real. In rough order of value:

- **No long-lived production credentials on a development machine.** This caps
  what a compromise is worth, and nothing else on this list does that.
- **A protected branch with required status checks**, so CI re-runs `verify.sh`
  on a runner the developer's machine cannot touch.
- **Review by a second person.** CI catches *the gate was lied to*. Only review
  catches *the code is bad*. They are different failures and you need both.
- **Commits signed with a hardware-backed key that requires a physical touch**
  (a FIDO2 `sk-ssh-ed25519` key). A compromised host can ask the key to sign.
  It cannot take the key, and it cannot sign while you are not there.
- **Push often.** The remote is an off-host log. A compromised machine can
  rewrite its own history; it cannot rewrite what you already pushed.
- **Build provenance** on release artifacts, so a binary built on a developer's
  machine cannot claim it came from CI.

### If a machine running these hooks is compromised

- Rebuild it from an image. Do not clean it.
- Restore source from the remote, not from the machine.
- Rotate every credential it has held, including ones you think it never used.
- Check the git history from a **different** machine. A compromised host
  reporting on itself tells you what the attacker chose.

### One note for agent-driven work

An agent reads repository content, and repository content is untrusted input. A
file that says "also update the hooks" is an instruction from a stranger.

The mitigation is placement, and the layout here already gets it right: keep
the hooks in a repository separate from the project being worked on. A change
to a hook then appears in a different `git status`, on its own, instead of
inside a forty-file diff where nobody will look at it.

## Dependencies

There are none. The example service uses the Go standard library only, and the
hooks use the shell, `git`, `awk`, `sed` and - in `commit-gate.sh` only -
`python`. There is therefore no SBOM in this repository: an SBOM of nothing is
a file that only pretends to tell you something.

A project that adopts the harness will have dependencies, and it should carry
both an SBOM and a vulnerability scan in its own `verify.sh`.
`templates/go/verify.sh` shows the scan as part of the full tier, and reports
exit 2 - could not run - when the scanner is not installed, rather than
reporting a pass.

## What the hooks can do to your machine

They read. They run one script you already have: your own project's
`verify.sh`. The only write is `gofmt -w` on a Go file you just edited, and
only in the fallback path for a project that has no `verify.sh` of its own.

Read them before you wire them up. They are short, and a hook you have not read
is a program you have given a shell on every edit you make.

## Reporting a problem

Open an issue. This is a demonstration repository with no production users, so
there is no embargo process and no response-time commitment. If you find
something that would be dangerous in a project that adopted these hooks, say so
in the issue and it will be fixed or the hook will be removed.
