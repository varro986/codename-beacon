# 2. PowerShell 7

Date: 30/10/2026

## Status

Accepted

## Context

Beacon grows from earlier diagnostics scripts. There, PowerShell only drove the run (cloud login, pod, parsing) and
the probes were Linux tools inside a pod (curl, nc, tcptraceroute, dig, jq, python). The common rules prefer C#, bash
and PowerShell 7, the same on Windows and Linux.

## Decision

Beacon is written in PowerShell 7. The probes use the .NET classes PowerShell 7 ships with, not external tools or
Windows-only cmdlets:

- DNS: `System.Net.Dns`, not `Resolve-DnsName` (Windows only).
- TCP: `System.Net.Sockets`, which tells a refused connection from a timeout.
- TLS: `System.Net.Security.SslStream`, for the certificate, chain, name and dates.
- HTTP and proxy: `System.Net.Http.HttpClient`; its connect callback can pin a request to one address (IDEA-13).

Tests with Pester, lint with PSScriptAnalyzer.

## Consequences

- One runtime on Windows, Linux and in a container; no BOM and line-ending workarounds of Windows PowerShell 5.1.
- Some probes are harder than in C#: the route (a TCP trace needs raw sockets or a TTL loop, possibly privileges) and
  NTLM are to be verified on Linux in the first plan; if one is not doable, the fallback is written there.
- Inside a pod, `pwsh` must be in the image.
- If the engine outgrows scripts (performance, the web interface of ADR 0001), moving it to C# is a new ADR; the
  result format (ADR 0003) keeps the interfaces independent of the language.
