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
- **Chain per target**: DNS once on the host; route once to the first resolved address (informs, never stops); a
  port check per port, ranges expanded (at most `MaxPortsPerTarget`, else an input error: Beacon does not scan); for
  each URL, TLS when it is `https` and then HTTP, run only if the URL's port opened (added to the ports when not
  listed). A failure marks every later check of the same target, or of the same URL, `SKIP` with the reason. Targets
  run one after the other, in the order of the matrix sorted by group and name. A port failure gets the route's last
  answering hop appended to its detail.
- **URL through a proxy** (`Resolve-BeaconProxy` says so): the URL's port check goes to the proxy (subject
  `proxy <host>:<port>`), the direct TLS check is not run, and the HTTP check reports TLS errors met inside the
  tunnel. Declared `Ports` are still checked directly.
- **Shared helpers** (`Private/Common.ps1`, T0): `Get-BeaconConfig` (defaults, environment overrides),
  `New-BeaconCheckRecord -Check -Subject -Status -Detail -DurationMs [-Data]` (the record of the schema without
  `group` and `target`, which the chain adds), `New-BeaconInputError -Message` (an `ErrorRecord` with id
  `BeaconInput`: exit code 2).
- **Check**: every check is a pair. A probe does the network I/O and returns raw facts; a pure outcome function turns
  facts + expected outcome + config into a record. Tests drive the pure half with facts, the probe half against local
  listeners (`TcpListener`, `HttpListener`, an `SslStream` server with a certificate made in the test). The chain calls
  only the entry of each check:

  | Task | Entry | Returns |
  |---|---|---|
  | T3 | `Invoke-BeaconDnsCheck -HostName <string> [-ExpectedAddresses <string[]>] -Config` | one record; `data.addresses`, `data.servers` (from `NetworkInterface` DNS addresses) |
  | T4 | `Invoke-BeaconRouteCheck -Address <string> -Config` | one record, `INFO` or `SKIP`; `data.hops`, `data.lastAnswering`, `data.method` |
  | T5 | `Invoke-BeaconPortCheck -Address <string> -Port <int> -Config` | one record; `data.reason` (`refused`, `timeout`, `unreachable`), `data.sourceAddress` |
  | T6 | `Invoke-BeaconTlsCheck -HostName <string> -Address <string> -Port <int> -Config` | one record; `data.subject`, `data.issuer`, `data.notAfter`, `data.errors` |
  | T7 | `Invoke-BeaconHttpCheck -Url <string> [-MatrixProxy <string>] [-ExpectedStatus <int[]>] -Config` | one record; `data.status`, `data.proxy` (URL or `direct`), `data.location`, `data.expected` |
  | T7 | `Resolve-BeaconProxy -Url <string> [-MatrixProxy <string>] [-Environment <IDictionary>]` | pure: the proxy URI for this URL, or `$null` for direct; `-Environment` defaults to the process environment |

- **Matrix** (T2): `Read-BeaconMatrix -Path` returns the data file or throws a `BeaconInput` error naming the entry
  (for example `Environments.test.Groups.web.Targets[1]: Host is missing`). `Get-BeaconTargets -Matrix -Environment`
  returns `@{ Proxy; Targets = @(@{ Group; Name; Host; ExpectedAddresses; Ports <int[]>; Urls; ExpectedStatus <int[]>;
  SecretEnv }) }`, ports expanded and sorted.
- **Chain and result** (T8): `Invoke-BeaconChain -Target <from Get-BeaconTargets> [-MatrixProxy] -Config` returns the
  target's records with `group` and `target`. `New-BeaconRun -Environment -Config` writes the result file at once with
  `complete = false`; `Add-BeaconRecords` and `Complete-BeaconRun` rewrite it (write only if different, atomic: temp
  file then move). The run folder is `<RunsFolder>/<yyyyMMdd_HHmmss>/result.json`.
- **Report** (T9): `Get-BeaconTotals -Result` (pure: totals per status, per group and per target, `INFO` excluded) and
  `Write-BeaconReport -Result` (the coloured table on the console).
- **Decisions of the owner (30/10)**: route TCP, then ICMP, then `SKIP`; proxy from the matrix, then the environment
  variables; TLS against the system trust store only, an own CA is an open question; exit codes 0 / 1 / 2; `GET` only,
  redirects not followed, at most `Http.PreviewChars` of the body in the detail when not `OK`.

## Risks

- **Route on Linux**: `Test-Connection -Traceroute` uses ICMP; a TCP trace needs a TTL loop on a raw socket,
  possibly with privileges. T1 tries both on Windows and Linux; if neither works unprivileged, the route reports
  `SKIP` with the reason (the chain does not depend on it).
- **TLS details**: `SslStream` validation callbacks differ slightly between Windows and Linux (chain errors); tests
  run on both in CI.
- **NTLM** (ADR 0002): not needed here (no authentication in this feature); verified with the feature that brings
  IDEA-14.
- **Proxy**: the system proxy (Windows settings, PAC) is not read: it differs by OS.
- **Local tests and DNS**: the "does not resolve" test uses a name under `.invalid` (RFC 6761); a resolver that
  answers for every name breaks it, and the test then says so.

## Tasks

| Id | Files touched | Depends on | Role | Done when |
|---|---|---|---|---|
| T0 | `contracts/*`, `src/Beacon/Beacon.ps*1`, `config/defaults.psd1`, `Private/Common.ps1`, `cicd/*`, `.github/workflows/cicd.yml`, `tests/Contracts.Tests.ps1`, `AGENTS.md` (Verification) | - | Orchestrator | `cicd/run.ps1` passes on the empty module and validates the examples |
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
A value an executor needs and does not find in `config/defaults.psd1` is reported, not added: the orchestrator adds it.
