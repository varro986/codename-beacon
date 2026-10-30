# Beacon: agent instructions

Rules for any coding assistant working on this repository. `CLAUDE.md` only imports this file.

<!-- BEGIN common rules: maintained centrally and copied identical into every product; do not edit here -->
## Common rules

The same in every repository of this family, private or public. A project that does something differently writes the
exception next to the rule it breaks, with the reason. Rules of a single project live in its README, "Rules".

### Goal

- **The perfect system**: every part does one thing, well, the same way as the others; nothing superfluous, nothing
  incoherent, nothing untested. When in doubt between two paths, take the one that gets closer to this.
- **Desired state and idempotence**: the wanted state lives in git and the code brings the system there; every step,
  repeated, does nothing; on an aligned system the dry run proposes no action.

### Single neutral source

- Rules live in plain text: `AGENTS.md` for a repository, the README for a project. `CLAUDE.md`, `GEMINI.md` and
  similar files only import them; skills, agents, commands and hooks of a tool never add rules of their own.
- Whatever must always hold (secrets, style, tests) also runs without AI, in pre-commit and in CI, with the same rules
  as the local hooks.
- **Context lives in the repository, never in a session, a machine or a tool's memory**: work moves between machines
  and sessions, so the state of the work is written where every session finds it: the project's files
  (`brainstorming.md`, the tasks of a plan, the README) and the owner's backlog for the direction. A session ends by
  writing that state. An assistant's own memory keeps only personal preferences; a rule that holds for a repository
  goes into its `AGENTS.md` or the norm.

### Behaviour

How every assistant works, in every project. The block between the markers is also, word for word, the instruction
the owner gives to chat assistants.

<!-- BEGIN behaviour -->
- **Replies**: in the owner's language unless asked otherwise; dry and direct. Long answers: a one-line summary first,
  then bullet points. Short answers: direct, no recap.
- **Facts**: numbers, standards, dates, health and money from authoritative sources, cited. When unsure, say so;
  keep facts apart from assessments; never invent.
- **Red team on ideas and decisions**: never complacent. Point out the main flaws and for each one a countermeasure
  or a workable alternative; take the weak version apart to build a stronger one. Operational requests (write, fix,
  translate, summarise) are simply carried out.
- **Ambiguity**: one question before answering.
<!-- END behaviour -->
- **Re-entering a project**: the first step is checking that it is aligned with the current norm (the guardian's
  deterministic checks) and reading the guardian's report next to the brainstorming; a change of the norm and the
  report's findings come before new work.

### The guardian's report

Next to `brainstorming.md`, a project may have the guardian's report (the file name is in the guardian's data): the
findings of the last review of that project, as a table `File | Problem | Choice`, most severe first, in the
project's language. Every finding is something out of place, and the owner has two choices: **integrate** it into
the norm (it is better than the norm: the norm grows and spreads it) or **rectify** it (the project goes back to the
norm); the guardian recommends one and says why. The guardian writes the report; the project's session reads it on
re-entering, applies the owner's choice, and removes each finding once settled. An empty report is deleted: git keeps
the history.

### Language

- English for identifiers, keys, file and folder names and commit messages. Documentation, comments and logs follow
  the repository: see its own rules.

### Safety and operations

- Before every change: can it destroy, replace or overwrite files? Can it touch data that is not its own? If so, stop
  and ask. Every write, move or delete has an explicit path, condition and protection (write only if different, copy
  first, atomic, never outside the expected folders).
- **Two branches, always**: `dev` is always open and always ahead; work happens there, with free commits. Every push,
  ordered by the owner, brings `main` level with `dev` once the checks pass, never anything else on `main`: in a product
  a merge commit whose message says what it brings (the report of the work), in a lab a fast-forward. The executors' worktrees are local branches that end
  in `dev` and are thrown away.
- Agents push and merge only when the person driving the session asks; never skip hooks (`--no-verify`); never
  run destructive commands (`rm -rf`, `reset --hard`, `push --force`, recursive deletions).
- Secrets never in the repository, in logs, results, reports or visible process arguments; only their names in the
  code. gitleaks in pre-commit and in CI. Where a secrets file is needed, a `.example` with the same names and no
  values sits next to it, kept aligned by a test.
- Least privilege everywhere: every account, service or command has only the permissions it needs (one database and
  account per project, read-only where enough).

### Permissions of coding assistants

Written once, in the repository's `.claude/settings.json` (under git, the same in every repository of a kind, checked
by the guardian); personal settings of a machine hold nothing else than what is personal. Roles as in "Working with
agents".

| Action | Orchestrator | Executor | Microtask | Reviewer |
|---|---|---|---|---|
| Read the repository | yes | yes | yes | yes |
| Read secrets (`*.env` with values, password manager exports, keys, `gh auth token`) | never | never | never | never |
| Edit inside the repository | yes | only its task's files, in its worktree | no | no |
| Edit outside the repository | only the places the repository's `AGENTS.md` names | no | no | no |
| Run tests and tools | yes | yes | read-only tools | yes |
| Commit on `dev` (or a local worktree that ends in `dev`) | yes, freely | never | never | never |
| Commit on `main`, push, merge, open or merge a pull request | only when the owner orders it, confirmed each time | never | never | never |
| Destructive commands (force push, hard reset, clean, recursive delete) | never | never | never | never |

### Code

- **Values in one place**: no numbers, times, paths or thresholds hard-coded; configuration holds them. A path or value
  that differs from one machine to another comes from an environment variable, with its default in configuration.
- **Clean and lean**: remove what is not needed (files, keys, sections), no dead code, no useless work (repeated reads,
  calls or queries, scans where a map is enough, queries without a time filter); the simplest form that does the job,
  no abstraction for a single use. Comments useful but minimal: only the non-obvious why, constraints, edge cases;
  never history dates.
- **Tested locally first**: every project with code has a `cicd/` folder with its deterministic checks (tests, syntax,
  alignment with configuration), run on the machine before every push by one shared runner. The remote CI runs the same
  steps, never different ones, and only what one of these needs: a guard that must hold even if a machine is wrong (the
  secrets scan on every push; the merge gate of a protected `main`), something the machines cannot do (another
  operating system), or what costs nothing and takes little. Never remote: checks whose rules are private, secrets,
  long jobs where minutes are paid.
- **Testable**: logic in small pure functions, I/O at the edges; a test for every important behaviour (writes,
  idempotence, secrets) and for every fixed bug. Formats exchanged between projects have an example tested by both the
  writer and the reader.
- **Design patterns where they help** (layers, adapters, configuration-driven behaviour), without over-engineering:
  code is mostly written by machines, and well-known patterns are how the owner reads and verifies it.
- **Observable**: every run leaves a result (what it did, counts, outcome) and logs that say what happened; an error is
  always visible and says what to do.
- **Reuse**: use what already exists; duplicated code goes to a common place. Code useful to more than one project is
  a candidate for the shared product, the base of all the owner's technology (its name in the guardian's data).
- **PowerShell 7 (pwsh) everywhere**, the same on Windows and Linux; the only exception is a Windows first-run script,
  compatible with Windows PowerShell 5.1, which installs pwsh and stops. No absolute machine paths in scripts (relative
  to the script or from `$HOME`), no Windows-only commands without the alternative next to them.
- No new feature without the owner's yes: ideas are proposals.

### Coherence and consistency

- **Consistency, the form**: the same thing has the same shape everywhere: names (written the same way, renamed
  everywhere in one change), README sections, statuses of ideas, file and folder names, formats, commands and their
  options (dry run and apply), results, logs and messages that say what to do. What can be checked by a tool is
  checked by a tool.
- **Coherence, the substance**: no two places say different things. Every fact has one source; the other places link
  to it instead of repeating it. A contradiction (README against code, configuration against documentation, a
  brainstorming against its README, one project against another) is a finding: it is settled at the source, or written
  as an open question until the owner decides.
- **One system**: projects are parts of one coherent whole; the same thing is done the same way everywhere. A new
  solution in one project holds for all of them, or the reason why not is written.
- **In the same change**: every code change updates README, configuration and tests together.
- **One project per session**: a session declares at the start which project it works on, stays in its folder and asks
  before touching another project; changes that span projects are declared as such.
- **Related projects**: every link (one uses, hosts or reuses another) is in the Dependencies table of the README, on
  both sides.

### Brainstorming

Every project has one `brainstorming.md`: where ideas and doubts wait for a decision, and only those. Two sections:

- **Ideas**: a table `Id | Date | Idea | Status`, one idea per row (`IDEA-n`, the date of origin). Ids are never
  reused: a line `Last id: IDEA-n` under the table keeps the highest one ever given.
- **Open questions**: doubts and contradictions to settle before deciding, one per line, with their date of origin.

Brainstorming converges and empties: a session on a project starts from it, asks the owner every open question and
every proposed idea at once, each with a recommendation, so that what is left to development is already decided. What
gets decided leaves the file and lives in one place only:

- **accepted**: the idea moves to its target (a feature whose `spec.md` cites `IDEA-n`, an ADR, a README section, the
  norm, another project's brainstorming, the backlog) and its row is removed; git keeps its history.
- **answered**: the answer goes where it belongs and the question is removed.
- What stays has one of two statuses (in an Italian repository: proposta, scartata): `proposed` (still to examine, or
  waiting for something) or `rejected: <reason>` (kept, so the same idea is not proposed again). An idea that repeats
  another is folded into it.

A `proposed` idea or an open question left without an answer for long is a finding of the guardian: it is brought to
the owner, not left to age.

What reaches it is already clean: no personal data, customer data or employer data, whatever the repository.

### Best of breed

- For every need, the standard or tool recognised as the best in its category, not an invented format: decisions as
  ADRs, architecture with arc42 and C4, quality with ISO 25010, acceptance criteria as Given/When/Then. Used in the
  reduced form the project needs, not in full.
- An exception (an own format, a less common tool) only with its reason written next to it; when the reason no longer
  holds, switch to the standard.

### Technologies

- The README declares the technologies used (languages, runtimes, services and main versions).
- Preferred: C#, bash and PowerShell 7. Anything else only when needed, with the reason written in the README.
- Dependencies, tools and languages: open source under MIT or Apache 2.0, portable across Windows and Linux; another
  licence, or something that runs on one system only, only with the reason written in the README.

### README

Five fixed sections say what the project is; five more, only when needed, say how to work on it. Names and order as
here; a section is omitted, never renamed. What would be a list of ideas or things to do goes to `brainstorming.md`,
not to the README.

1. `# <Name>` and one line: what it is.
2. Goal: why it exists, what problem it solves, for whom (1-3 lines).
3. Description: what it does and where it runs, in a few lines.
4. Technologies: languages, runtimes, services, main versions; for anything not C#, bash or PowerShell, the reason.
5. Dependencies: table `From | What it uses | Type` (project, library, service, machine), or "None"; also who depends
   on this project.
6. Architecture (when needed): the folder tree (code block, one line per entry), components and flows; a mermaid
   diagram only if needed.
7. Rules (when needed): the project's own.
8. Usage (when it is installed or run): installation, commands, how to change and ship.
9. Tests (when there is code): the `cicd/` steps and how to run them.
10. Agents (when work is split): what runs in parallel and who does it, contracts not to touch, what stays with the
    owner.

A repository documented in Italian uses the same sections with Italian titles (Obiettivo, Descrizione, Tecnologie,
Dipendenze, Architettura, Regole del progetto, Uso, Prove, Agenti).

### Working with agents

Roles are by model tier, so they hold with any assistant; the "today" column is the current choice.

| Role | Today (Claude) | Does | Does not |
|---|---|---|---|
| Orchestrator | Opus 5.5, high effort (max for architecture) | plan, contracts and interfaces (first, in series), decisions, wiring, build, tests, commits | mechanical work it can delegate |
| Executor | Sonnet 5.5 | one task at a time, in an isolated worktree, in parallel with the others; touches only its files | build, commits, contract changes |
| Microtask | Haiku 5.5 | searches, test stubs from the criteria, renames, mechanical checks | decisions |
| Reviewer | Sonnet 5.5, fresh agent | reads the diff with fresh eyes, runs the tests, checks the criteria | fixing things itself |

- **Deterministic work goes into tools, not into reasoning**: whatever is done the same way every time (checks,
  scaffolding, counting, formatting, syncing) becomes a script, which costs no tokens and always gives the same
  result; agents run the tools, read their results and keep for themselves only what needs judgment. When an agent
  does the same deterministic job by hand twice, the next step is a tool. A project keeps its tools together in
  `tools/`, each with its usage written at the top, so any agent finds them in the same place.
- Only what touches different files runs in parallel: never two agents on the same file, never two on the same task.
- A new agent's prompt says everything (files to read, boundaries, what to report): it does not see the conversation.
- Every agent reports files changed, tests written or run and doubts; never "done" without saying what was verified.
- Small jobs are done, not delegated. Real data and production: the agent prepares, the owner approves and ships.
- **Unsupervised work**: the owner decides first (a converged brainstorming, criteria as tests), then the machine works
  alone on `dev`. A missing decision is never guessed: it becomes an open question in `brainstorming.md`, the
  owner is notified, and the work moves to a task that does not depend on it. A session has a limit (tasks or time) and
  stops when the same check fails twice in a row. It ends with a report: tasks done, checks run, open questions; the
  owner reads that, not the session, and orders push and merge.
<!-- END common rules -->

<!-- BEGIN product rules: maintained centrally and copied identical into every product; do not edit here -->
## Product rules

What holds for every product, on top of the common rules.

### A product

- A public repository with its own philosophy, meant for more people: issues, pull requests, contributors.
- **Self-sufficient**: whoever opens it sees only the repository, so everything needed to work on it (architecture,
  decisions, rules) is in it. No personal data, customer data or employer data anywhere, not even in notes or test
  fixtures.
- Documentation, comments and logs in English.

### Workflow

- `main` is protected, for everyone: it changes only through a pull request from `dev`, merged with a merge commit
  once CI is green (common rules, "Two branches, always").
- MIT licence. Community files: `SECURITY.md` (private vulnerability reporting), `CODE_OF_CONDUCT.md` (Contributor
  Covenant 2.1), issue forms, pull request template, Dependabot.

### Spec driven development

The product is built from its specs, on a reduced GitHub Spec Kit model: constitution (`AGENTS.md`), spec, plan with
its tasks, implementation. The README is the vision. The layout below is the required skeleton; entries marked
`(when needed)` and names with `NNN` are added as the work requires them.

```
|-- README.md, AGENTS.md, CLAUDE.md, CONTRIBUTING.md, LICENSE, SECURITY.md, CODE_OF_CONDUCT.md
|-- .gitignore, .gitleaks.toml, .editorconfig
|-- .githooks/
|   \-- pre-commit               gitleaks on staged files
|-- .github/
|   |-- workflows/               CI: gitleaks, then the cicd/ steps on pull requests
|   |-- ISSUE_TEMPLATE/          bug report and idea forms
|   |-- pull_request_template.md
|   \-- dependabot.yml           updates of dependencies and GitHub Actions
|-- .claude/
|   |-- settings.json            permissions of coding assistants (common rules, "Permissions")
|   \-- agents/                  executor.md, reviewer.md, microtask.md: model and tools only (when needed)
|-- specs/
|   |-- brainstorming.md
|   |-- architecture.md          reduced arc42 + C4, quality goals, glossary (when needed)
|   |-- decisions/               ADRs (Nygard), never edited: a changed decision is a new ADR (when needed)
|   |   \-- NNNN-title.md
|   \-- features/                one folder per feature: the unit of work
|       \-- NNN-name/
|           |-- spec.md          the idea it comes from, stories and Given/When/Then criteria (what)
|           \-- plan.md          how: components, contracts, risks; then the tasks table: id, files touched,
|                                depends on, role, "done when"
|-- cicd/                        the product's local checks, run before every push (common rules, "Code")
|-- src/
|-- tests/
\-- tools/                       deterministic tools for agents and people (common rules, "Working with agents")
```

- `specs/brainstorming.md` is the product's brainstorming (common rules, "Brainstorming") while only the owner works
  on the product; with contributors, GitHub Issues take the place of its ideas.
- An idea becomes work only with the owner's yes: it becomes a feature whose `spec.md` cites it (`IDEA-n`) and leaves
  `brainstorming.md` (common rules, "Brainstorming"). "Done when" points to the Given/When/Then criteria, so it is a
  passing test.
- A file is added when it is needed, not before. The README stays short and points to `specs/`.

### Parallel work from the tasks

- Tasks are written to be parallel: each declares the files it touches and what it depends on. Two tasks with no
  shared files and no open dependencies run together, one executor each in its own worktree.
- Contracts and interfaces from `plan.md` come first, written by the orchestrator in series; no executor changes them.
- The reviewer checks the diff against the criteria in `spec.md`.
<!-- END product rules -->

## Beacon rules

None yet beyond the common rules. What the product is: `README.md`; what it must do: `specs/`.

## Verification

Commands the orchestrator runs before a commit: none yet (no code). They are added here with the first code.
