# Security

## What this repository is

Four shell scripts that run as editor hooks, a shell template, and a stub Go
service that exists so the scripts have something to act on. It is a
demonstration. Nothing here is a service, and nothing here should be exposed to
a network.

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
