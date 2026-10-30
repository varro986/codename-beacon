# Brainstorming

Ideas and doubts waiting for a decision. An accepted idea leaves this file for its target; only proposed and rejected
ideas stay.

## Ideas

| Id | Date | Idea | Status |
|---|---|---|---|
| IDEA-1 | 30/10 | A web interface for the network tests (to be confirmed). (voice note 30/10) | proposed |
| IDEA-2 | 30/10 | While traces run, draw a map of the network topology and of the hops, showing where traffic opens and where it is blocked, so bottlenecks stand out (for example everything passing through one perimeter firewall). (voice note 30/10) | proposed |
| IDEA-3 | 30/10 | Every IP on the map can be labelled with a name that is reused across runs. (voice note 30/10) | proposed |
| IDEA-4 | 30/10 | Local first: results go into a local database that can be exported and handed to someone else. (voice note 30/10) | proposed |
| IDEA-5 | 30/10 | Instead of a handful of scripts, a set of tools (possibly agents) that run the network investigations. (voice note 30/10) | proposed |
| IDEA-6 | 30/10 | Tools run wherever they are needed: inside a container when the context is a container, elsewhere otherwise. (voice note 30/10) | proposed |
| IDEA-7 | 30/10 | Excel is the lasting format: tools read spreadsheets and always export to spreadsheets, freely readable per project; SQLite or similar only as a temporary store. (voice note 30/10) | proposed |
| IDEA-8 | 30/10 | The graphical reconstruction of the network maps is a key output. (voice note 30/10) | proposed |

Last id: IDEA-8

## Open questions

- Web interface or desktop app? The README still has the stack open (PowerShell 7 or C#). (voice note 30/10)
- Which tests make the first version (trace, ports, DNS, TLS...)? (voice note 30/10)
- Is the map meant to cross organisations (paths that leave one network and enter another)? (voice note 30/10)
- The scripts, tests and knowledge collected so far: the owner will share them, to extract implicit requirements into this brainstorming. (voice note 30/10)
- Which stack: PowerShell 7, like the script it comes from, or C#? To record as an ADR. (README, To do)
- Which checks make the first version, and which report format? (README, To do)
