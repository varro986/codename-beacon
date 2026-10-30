# Beacon

A network diagnostics tool: it runs every test that makes sense on a network and shows where traffic stops.

## Goal

When something does not get through, answer quickly where it is blocked (DNS, routing, firewall, proxy, TLS, the
service itself) without running a dozen tools by hand and stitching the results together.

## Description

Beacon traces the path to a target and scans the network along the way, running the full set of checks it can (from
name resolution and reachability to ports, proxies and certificates), then reports the first point where things
break and why. It starts from the experience of an earlier PowerShell diagnostics script and grows it into something
richer: more checks, more ideas, a clearer report. It runs from the command line first; a local web interface comes
later ([ADR 0001](specs/decisions/0001-cli-first-then-local-web.md)). The first feature is the
[diagnostic chain](specs/features/001-diagnostic-chain/spec.md).

## Technologies

- PowerShell 7, on Windows, Linux and in containers; probes through the .NET classes it ships with
  ([ADR 0002](specs/decisions/0002-powershell-7.md)).
- Pester for tests, PSScriptAnalyzer for lint.
- Results as JSON, one record per check ([ADR 0003](specs/decisions/0003-run-result-format.md)).

## Dependencies

None yet. Nothing depends on Beacon.

## Architecture

```
codename-beacon/
|-- README.md         what the project is
|-- AGENTS.md         rules for coding assistants: common rules, then the product's own
|-- CLAUDE.md         shell for Claude Code (@AGENTS.md)
|-- CONTRIBUTING.md   how to contribute (specs first, dev then main)
|-- LICENSE           MIT
|-- SECURITY.md       how to report a vulnerability
|-- CODE_OF_CONDUCT.md
|-- specs/            brainstorming.md; architecture as it comes
|   |-- features/     one folder per feature: spec.md, plan.md with its tasks
|   \-- decisions/    ADRs
|-- cicd/             local checks run before every push: run.ps1
|-- src/Beacon/       the PowerShell module: matrix, checks, chain, result, report
|-- tests/            Pester tests, from the acceptance criteria
|-- tools/            deterministic tools for agents and people
|-- .githooks/        pre-commit: gitleaks on staged files
|-- .github/          CI (gitleaks; cicd/run.ps1 on Linux and Windows), issue and PR templates, Dependabot
|-- .gitleaks.toml    secret scan rules
|-- .gitignore
\-- .editorconfig     shared editor settings
```

## Rules

- **Only on networks you are allowed to test**: scanning a network you do not own or have no permission for is not a
  use case.
- **Read-only by default**: Beacon observes and reports; it never changes network or system settings. A check that
  writes data (for example a test file in a storage) is off by default, enabled only by its profile, never in
  production; it asks for confirmation and always removes what it wrote.

## Tests

`pwsh -NoProfile -File cicd/run.ps1`: lint and Pester tests, the same steps as the remote CI
([cicd/README.md](cicd/README.md)).

