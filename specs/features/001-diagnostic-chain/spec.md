# 001 Diagnostic chain

From the README goal (answer quickly where traffic to a target is blocked), IDEA-9 (targets from a declarative matrix),
IDEA-10 (expected outcome per check) and IDEA-12 (egress identity, local data only). First feature of the first
version.

## Stories

- As someone whose connection to a service fails, I give Beacon one target (a name or address, a port, optionally a
  URL) and it tells me the first point where things break and why, without running the tools one by one.
- As someone who checks a whole environment, I describe its targets once in a matrix and Beacon runs the chain on
  each of them, telling apart what is really blocked from what answers as expected.

## The chain

The checks run in this order; each one runs only if the previous one passed, because a later check cannot tell
anything useful when an earlier one failed. The route is the exception: it informs and never stops the chain, because
many networks drop trace packets while the service itself is reachable.

1. **DNS**: the name resolves, and to which addresses, through the system resolver.
2. **Route**: the path to the address, hop by hop, and the last hop that answers. TCP trace when possible, ICMP
   otherwise; when neither works without privileges, the route is skipped with the reason.
3. **Port**: a TCP connection to the target port opens.
4. **TLS**: the handshake completes; certificate, chain, name and dates are valid against the system trust store.
5. **HTTP**: a `GET` gets an answer, directly or through the proxy; redirects are reported, not followed.

The proxy is the environment's `Proxy` in the matrix; without it, `HTTPS_PROXY`, `HTTP_PROXY` and `NO_PROXY` as curl
reads them; otherwise direct. Through a proxy it is the proxy that resolves the name: a URL through a proxy is
checked even when the target's name does not resolve on the machine. A proxy's credentials are never shown nor
stored; the matrix does not accept them.

A URL whose host differs from the target's is checked against its own host: its name is resolved on its own, so the
port, TLS and HTTP checks of that URL test the same server.

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
- Given a network that drops trace packets, when Beacon runs, then the route shows the last hop that answered and the
  later checks still run.
- Given a port that is closed or filtered, when Beacon runs, then the outcome points to the port, says whether it was
  refused or timed out, and shows the last hop of the route that answered.
- Given a certificate that is expired, untrusted or for another name, when Beacon runs, then the outcome points to TLS
  and says which of these is wrong.
- Given a proxy that blocks or rejects the request, when Beacon runs, then the outcome points to the proxy and shows
  its answer. For a plain `http` URL, where a refusal of the proxy and one of the service look the same, a 403 is a
  warning that says either may have refused.
- Given an HTTP check with no expected outcome, when it answers, then a timeout is a failure, 2xx and 3xx pass, 4xx and
  5xx are warnings.
- Given an HTTP check whose expected outcome is a status (for example 401), when it answers with that status, then the
  check passes and the detail says it was expected.
- Given a URL that answers with a redirect, when Beacon runs, then the check passes and the detail shows where it
  points, without following it.
- Given a matrix with several environments, when Beacon runs on one of them, then only that environment's targets run
  and the console totals are per group and per target.
- Given a matrix that is not valid (missing host, unknown field, a value where a secret name is expected), when Beacon
  starts, then it stops before any check and says which entry is wrong and how to fix it.
- Given any run, when it ends, then it leaves the result of ADR 0003 with the checks run, their outcome and timings,
  the name of the machine it ran on and, for every port, the source address used.
- Given any run, when it ends, then the exit code is 0 when no check failed (warnings included), 1 when at least one
  failed, 2 when the matrix or the parameters are not valid (missing ones included).
- Given any run, when Beacon shows it on the console, then every detail is shown whole (long ones wrap), and each
  target's outcome line says where it is blocked and why.

## Out of scope

- Scanning hosts or ports beyond the targets of the matrix.
- Changing any network or system setting, and checks that write data (README, Rules).
- The public address of the machine (IDEA-12, it needs an external service).
- A certificate authority of one's own beyond the system trust store (open question in the brainstorming).
- The map and the web interface (ADR 0001).
