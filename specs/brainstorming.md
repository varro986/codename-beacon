# Brainstorming

Ideas and doubts waiting for a decision. An accepted idea leaves this file for its target; only proposed and rejected
ideas stay.

## Ideas

| Id | Date | Idea | Status |
|---|---|---|---|
| IDEA-2 | 30/10 | While traces run, draw a map of the network topology and of the hops, showing where traffic opens and where it is blocked, so bottlenecks stand out (for example everything passing through one perimeter firewall). The map shows one vantage point, where Beacon runs: hops beyond one's own network stay "external". The graphical reconstruction of the maps is a key output (was IDEA-8). (voice note 30/10) | proposed |
| IDEA-3 | 30/10 | Every IP on the map can be labelled with a name that is reused across runs; Beacon keeps the names in its database, where nodes are renamed and drawn. (voice notes 30/10) | proposed |
| IDEA-4 | 30/10 | Local first: results go into a local database that can be exported and handed to someone else. (voice note 30/10) | proposed |
| IDEA-6 | 30/10 | Tools run wherever they are needed: inside a container when the context is a container, elsewhere otherwise. The earlier scripts ran every probe from a disposable pod inside the target cluster, with pre-checks (login still valid, image available, pod ready) that fail fast with a hint, explicit context and cleanup. The owner sees this as a probe: Beacon carried where the test must run, returning its JSON result to the machine that shows it (owner, 30/10). (voice note 30/10; existing scripts 30/10) | proposed |
| IDEA-7 | 30/10 | Excel is the lasting format: tools read spreadsheets and always export to spreadsheets, freely readable per project; SQLite or similar only as a temporary store. Narrowed by the owner on 30/10: spreadsheets are import and export, the sources stay text (the target matrix, feature 001) and JSON (results, ADR 0003). (voice note 30/10) | proposed |
| IDEA-11 | 30/10 | DNS checked twice, through local overrides and through the real resolver, flagging a public address where a private one is expected. (existing scripts 30/10) | proposed |
| IDEA-12 | 30/10 | Every run reports its own public address too, through an IP echo service, for firewall allow-list requests. The local part (machine, source address) is in feature 001. (existing scripts 30/10) | proposed |
| IDEA-13 | 30/10 | A request can be pinned to one address behind a name (each load balancer address in turn), keeping the name for SNI and Host. (existing scripts 30/10) | proposed |
| IDEA-14 | 30/10 | Pluggable authentication flows (client credentials, custom grants, login then bearer, NTLM); a token is never logged beyond a short prefix and chosen claims. (existing scripts 30/10) | proposed |
| IDEA-15 | 30/10 | The same request sent directly and through a gateway: normalised JSON compared, the difference saved; optionally also against a stored reference answer. Tells which layer answered (load balancer, gateway, policy, service). (existing scripts 30/10) | proposed |
| IDEA-16 | 30/10 | History of runs per target: what opened or closed since the last run, in place of status tables kept by hand. (existing scripts 30/10) | proposed |
| IDEA-17 | 30/10 | Export the map as Mermaid, generated from the result JSON, to paste into a ticket, a wiki or a README where it renders. (owner 30/10) | proposed |
| IDEA-18 | 30/10 | Beacon as an application with one or more agents that talk to it, in the manner of a ServiceNow MID Server: containers on a pod or applications running wherever the tests must run; each agent sends a heartbeat and receives the commands to run, then returns the results. A step beyond the disposable probe of IDEA-6. (voice note 30/10) | proposed |
| IDEA-19 | 30/10 | The agents run a minimal set of Windows or Linux commands, already installed on the machine, that cannot do any harm (read-only). (voice note 30/10) | proposed |
| IDEA-20 | 30/10 | Where the commands cannot run, the agent writes a text report into a fixed folder on the machine, and only that report is sent to Beacon. (voice note 30/10) | proposed |

Last id: IDEA-20

## Open questions

- How do the agents talk to Beacon: the agent calls Beacon (heartbeat and pull of the commands, the MID Server way) or Beacon calls the agent? Over which protocol, and how does an agent prove who it is? (voice note 30/10)
- TLS trust: only the system trust store, or also a certificate authority file per environment in the matrix (an
  internal company CA not installed on the machine)? Feature 001 uses the system store only. (owner 30/10)
