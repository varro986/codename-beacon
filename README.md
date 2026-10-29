# Beacon

A network diagnostics tool: it runs every test that makes sense on a network and shows where traffic stops.

## Goal

When something does not get through, answer quickly where it is blocked (DNS, routing, firewall, proxy, TLS, the
service itself) without running a dozen tools by hand and stitching the results together.

## Description

Beacon traces the path to a target and scans the network along the way, running the full set of checks it can (from
name resolution and reachability to ports, proxies and certificates), then reports the first point where things
break and why. It starts from the experience of an earlier PowerShell diagnostics script and grows it into something
richer: more checks, more ideas, a clearer report.

## Technologies

To be decided (see "To do"). Constraints: runs on Windows and Linux, open source dependencies (MIT or Apache 2.0
preferred), checks as small testable units with the network I/O at the edges.

## Dependencies

None yet. Nothing depends on Beacon.

## Architecture

```
codename-beacon/
|-- README.md         what the project is
|-- AGENTS.md         rules for coding assistants: common rules, then the product's own
|-- CLAUDE.md         shell for Claude Code (@AGENTS.md)
|-- CONTRIBUTING.md   how to contribute (specs first, GitHub Flow)
|-- LICENSE           MIT
|-- SECURITY.md       how to report a vulnerability
|-- CODE_OF_CONDUCT.md
|-- specs/            ideas.md, questions.md; requirements, architecture and the rest as they come
|   |-- features/     one folder per feature: spec.md, plan.md, tasks.md
|   \-- decisions/    ADRs
|-- src/              source code
|-- tests/            tests, from the acceptance criteria
|-- .githooks/        pre-commit: gitleaks on staged files
|-- .github/          CI (gitleaks), issue and PR templates, Dependabot
|-- .gitleaks.toml    secret scan rules
|-- .gitignore
\-- .editorconfig     shared editor settings
```

## Rules

- **Only on networks you are allowed to test**: scanning a network you do not own or have no permission for is not a
  use case.
- **Read-only**: Beacon observes and reports; it never changes network or system settings.

## Miscellaneous

Nothing yet.

## To do

- Choose the stack (PowerShell 7, like the script it comes from, or C#) and record why.
- List the checks of the first version and the report format.
