# 001 Diagnostic chain: plan

How [spec.md](spec.md) is built, on ADR 0001 (command line first), ADR 0002 (PowerShell 7) and ADR 0003 (run result).

## Components

```
src/
|-- beacon.ps1                    command line entry: parameters, then Invoke-Beacon
\-- Beacon/                       PowerShell module
    |-- Beacon.psd1, Beacon.psm1
    |-- config/defaults.psd1      timeouts, hop limit, status mapping: every value in one place
    |-- Public/Invoke-Beacon.ps1  matrix or single target -> run -> result file + console table
    \-- Private/
        |-- Matrix.ps1            read and validate the matrix
        |-- Checks/               one file per check: Dns, Route, Port, Tls, Http
        |-- Chain.ps1             order, stop on first failure, SKIP for the rest
        |-- Result.ps1            run record, JSON writer, partial run marker
        \-- Report.ps1            console table and totals
tests/                            Pester, one file per component, plus a local end-to-end test
cicd/run.ps1                      PSScriptAnalyzer, Pester, contract examples against their schema
```

The engine (matrix, checks, chain, result) knows nothing of the console: the table, and later the local web server
(ADR 0001) and the probe carried into a pod (IDEA-6), only read and write the result of ADR 0003.

## Contracts

Written first, by the orchestrator; no executor changes them.

- **Matrix**: a PowerShell data file (`.psd1`), read with `Import-PowerShellDataFile` (safe: no code runs, comments
  allowed, no extra module). Example: `contracts/matrix.example.psd1`. Shape: `Environments` -> `Groups` ->
  `Targets`, a target with `Host`, `ExpectedAddresses`, `Ports`, `Urls`, `Expect` (per check), and per environment an
  optional `Proxy`. Secrets only as `SecretEnv = 'NAME'`.
- **Result**: JSON Schema (2020-12) `contracts/result.schema.json` and example `contracts/result.example.json`, the
  fields of ADR 0003.
- **Check**: every check is a pair. `Invoke-Beacon<Check>Probe` does the network I/O and returns raw facts.
  `Get-Beacon<Check>Outcome` is pure: facts + expected outcome + defaults -> record `{ check, status, detail,
  durationMs, data }`. Tests drive the pure half with facts, the probe half against local listeners.

## Risks

- **Route on Linux**: `Test-Connection -Traceroute` uses ICMP; a TCP trace needs a TTL loop on a raw socket,
  possibly with privileges. T1 tries both on Windows and Linux; if neither works unprivileged, the route reports
  `SKIP` with the reason (the chain does not depend on it).
- **TLS details**: `SslStream` validation callbacks differ slightly between Windows and Linux (chain errors); tests
  run on both in CI.
- **NTLM** (ADR 0002): not needed here (no authentication in this feature); verified with the feature that brings
  IDEA-14.
- **Proxy**: an explicit proxy from the matrix only; reading the system proxy differs by OS and waits.

## Tasks

| Id | Files touched | Depends on | Role | Done when |
|---|---|---|---|---|
| T0 | `contracts/*`, `src/Beacon/Beacon.ps*1`, `config/defaults.psd1`, `cicd/run.ps1`, `AGENTS.md` (Verification) | - | Orchestrator | `cicd/run.ps1` passes on the empty module and validates the examples |
| T1 | `tests/spikes/Route.Spike.ps1`, this plan (Risks) | - | Executor | the route method is chosen and written here, tried on Windows and Linux |
| T2 | `Private/Matrix.ps1`, `tests/Matrix.Tests.ps1` | T0 | Executor | criteria "several environments" and "matrix not valid" pass |
| T3 | `Private/Checks/Dns.ps1`, `tests/Dns.Tests.ps1` | T0 | Executor | criteria "does not resolve" and "other address" pass |
| T4 | `Private/Checks/Route.ps1`, `tests/Route.Tests.ps1` | T0, T1 | Executor | hop list and last answering hop from recorded facts |
| T5 | `Private/Checks/Port.ps1`, `tests/Port.Tests.ps1` | T0 | Executor | criterion "closed or filtered" passes (refused and timeout) |
| T6 | `Private/Checks/Tls.ps1`, `tests/Tls.Tests.ps1` | T0 | Executor | criterion "certificate" passes for expired, untrusted, other name |
| T7 | `Private/Checks/Http.ps1`, `tests/Http.Tests.ps1` | T0 | Executor | criteria "proxy", "no expected outcome", "expected status" pass |
| T8 | `Private/Chain.ps1`, `Private/Result.ps1`, their tests | T0 | Executor | chain order, SKIP after failure, route never stops it; result valid against the schema |
| T9 | `Private/Report.ps1`, `tests/Report.Tests.ps1` | T0 | Executor | table and totals per group and target from the example result |
| T10 | `Public/Invoke-Beacon.ps1`, `src/beacon.ps1`, `tests/EndToEnd.Tests.ps1` | T2-T9 | Orchestrator | every criterion of spec.md passes end to end against local listeners |
| T11 | - | T10 | Reviewer | the diff checked against spec.md, `cicd/run.ps1` green |

T1-T9 touch different files: after T0 they run in parallel, one executor each in its own worktree (T4 waits for T1).
