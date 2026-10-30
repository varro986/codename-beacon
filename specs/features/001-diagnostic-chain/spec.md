# 001 Diagnostic chain

From the README goal (answer quickly where traffic to a target is blocked), IDEA-9 (targets from a declarative matrix)
and IDEA-10 (expected outcome per check). First feature of the first version.

## Stories

- As someone whose connection to a service fails, I give Beacon one target (a name or address, a port, optionally a
  URL) and it tells me the first point where things break and why, without running the tools one by one.
- As someone who checks a whole environment, I describe its targets once in a matrix and Beacon runs the chain on
  each of them, telling apart what is really blocked from what answers as expected.

## The chain

The checks run in this order; each one runs only if the previous one passed, because a later check cannot tell
anything useful when an earlier one failed. The route is the exception: it informs and never stops the chain, because
many networks drop trace packets while the service itself is reachable.

1. **DNS**: the name resolves, and to which addresses.
2. **Route**: the path to the address, hop by hop, and the last hop that answers.
3. **Port**: a TCP connection to the target port opens.
4. **TLS**: the handshake completes; certificate, chain, name and dates are valid.
5. **HTTP**: a request gets an answer, directly or through the configured proxy.

## The matrix

A text file under version control, one per project: targets grouped by environment and group, each with host,
expected addresses, ports or port ranges, URLs, and optionally the expected outcome of a check. Secrets are referenced
by the name of an environment variable, never written in the matrix. Importing from and exporting to a spreadsheet is
not part of this feature (IDEA-7).

## Acceptance criteria

- Given a target that is reachable on every step, when Beacon runs, then every check is reported as passed and the
  outcome says the target is reachable.
- Given a name that does not resolve, when Beacon runs, then the outcome points to DNS, says what was asked to which
  server, and the later checks are reported as not run.
- Given a name that resolves to an address other than the expected one, when Beacon runs, then the DNS check is a
  warning that shows both addresses.
- Given a port that is closed or filtered, when Beacon runs, then the outcome points to the port, says whether it was
  refused or timed out, and shows the last hop of the route that answered.
- Given a certificate that is expired, untrusted or for another name, when Beacon runs, then the outcome points to TLS
  and says which of these is wrong.
- Given a proxy that blocks or rejects the request, when Beacon runs, then the outcome points to the proxy and shows
  its answer.
- Given an HTTP check with no expected outcome, when it answers, then a timeout is a failure, 2xx and 3xx pass, 4xx and
  5xx are warnings.
- Given an HTTP check whose expected outcome is a status (for example 401), when it answers with that status, then the
  check passes and the detail says it was expected.
- Given a matrix with several environments, when Beacon runs on one of them, then only that environment's targets run
  and the console totals are per group and per target.
- Given a matrix that is not valid (missing host, unknown field, a value where a secret name is expected), when Beacon
  starts, then it stops before any check and says which line is wrong and how to fix it.
- Given any run, when it ends, then it leaves the result of ADR 0003 with the checks run, their outcome and timings.

## Out of scope

- Scanning hosts or ports beyond the targets of the matrix.
- Changing any network or system setting, and checks that write data (README, Rules).
- The map and the web interface (ADR 0001).
