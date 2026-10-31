# Beacon: agent instructions

Rules for any coding assistant working on this repository. `CLAUDE.md` only imports this file.

<!-- BEGIN common rules: maintained centrally and copied identical into every product; do not edit here -->
## Common rules

The same in every repository of this family, private or public. A project that does something differently writes the
exception next to the rule it breaks, with the reason. Rules of a single project live in its README, "Rules". Rules
that a tool can check are checked by the guardian's tools; rules of judgment (Observable, Testable, Language, In the
same change, One project per session, Best of breed) are checked in the guardian's review, the report of each project.

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
- **Context lives in the repository, never in a session, a machine or a tool's memory**: the state of the work is
  written where every session finds it (`brainstorming.md`, the tasks of a plan, the README; the owner's backlog for
  the direction), and a session ends by writing it. An assistant's own memory keeps only personal preferences.

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
- **Re-entering a project**: first check that it is aligned with the current norm (the guardian's deterministic
  checks) and read the guardian's report; a change of the norm and the report's findings come before new work.
- **Sources before guesses**: when a project starts, or its requirements are thin, ask the owner for what already
  exists (documents, scripts, worksheets) and turn the implicit requirements found there into proposed ideas in its
  `brainstorming.md`.

### The guardian's report

Next to `brainstorming.md`, a project may have the guardian's report (the file name is in the guardian's data): the
findings of the last review, as a table `File | Problem | Choice`, most severe first, in the project's language. Every
finding is something out of place, with two choices for the owner: **integrate** it into the norm (it is better than
the norm, which grows and spreads it) or **rectify** it (the project goes back to the norm); the guardian recommends
one and says why. The project's session reads the report on re-entering, applies the owner's choice and removes each
finding once settled. An empty report is deleted: git keeps the history.

### Safety and operations

- Before every change: can it destroy, replace or overwrite files? Can it touch data that is not its own? If so, stop
  and ask. Every write, move or delete has an explicit path, condition and protection (write only if different, copy
  first, atomic, never outside the expected folders).
- **Branches, and nothing else**: a product has two, a lab has one. In a product `dev` is always open and always ahead;
  work happens there, with free commits; every push, ordered by the owner, brings `main` level with `dev` once the
  checks pass, with a merge commit whose message says what it brings (the report of the work), never anything else on
  `main`. A lab has `main` only: work happens there, with free commits, and the owner orders the push. Nothing else
  lasts: the executors' worktrees are temporary and end in the working branch; the guardian writes in a product from a
  temporary detached worktree, without a branch of its own; any other branch or worktree, local or on the remote, is a
  finding of the guardian. Commits on the working branch not yet on the remote (a branch ahead of its upstream) are
  a finding too: a session that leaves any tells the owner at the end of its work, listing them, because the owner
  cannot see them from elsewhere; the push still waits for the owner's order.
- Never skip hooks (`--no-verify`); a test that a filter refuses something uses a harmless word, never the real thing.
- Before every commit the staged set is checked: only what is meant; with other agents in the clone, only the listed
  files.
- Installations made for a job (packages, environments, models, caches) are declared before and removed with the
  owner at the end, checking nothing is left; nothing new is installed on a machine without the owner's yes.
- Secrets never in the repository, in logs, results, reports or visible process arguments; only their names in the
  code. gitleaks in pre-commit and in CI. A secrets file has a `.example` next to it with the same names and no values,
  kept aligned by a test.
- Least privilege everywhere: every account, service or command has only the permissions it needs (one database and
  account per project, read-only where enough).

### Permissions of coding assistants

Written once, in the repository's `.claude/settings.json` (under git, the same in every repository of a kind, checked
by the guardian); personal settings of a machine hold only what is personal. Roles as in "Working with agents".

| Action | Orchestrator | Executor | Microtask | Reviewer |
|---|---|---|---|---|
| Read the repository | yes | yes | yes | yes |
| Read secrets (`*.env` with values, password manager exports, keys, `gh auth token`) | never | never | never | never |
| Edit inside the repository | yes | only its task's files, in its worktree | no | no |
| Edit outside the repository | only the places the repository's `AGENTS.md` names | no | no | no |
| Run tests and tools | yes | yes | read-only tools | yes |
| Commit on the working branch (`dev` in a product, `main` in a lab; or a temporary worktree that ends there) | yes, freely | never | never | never |
| Commit on a product's `main`, push, merge, open or merge a pull request | only when the owner orders it, confirmed each time | never | never | never |
| Destructive commands (force push, hard reset, clean, recursive delete) | never | never | never | never |

Guardrails against destroying anything outside the repository, in layers, because pattern rules alone are easy to get
around:

- **Sandbox** where the system has one: writes of shell commands only inside the repository and the temporary folders.
- **Guard hook** where hooks run, before every shell command: deletions, moves and overwrites outside the repository,
  or inside the owner's data stores, are refused; what it cannot resolve (variables, wildcards) is asked to the owner.
  It reads commands, not scripts: running a script outside `tools/` and `cicd/` stays a question to the owner.
- **Deny rules** everywhere: the guard's protected places as permission patterns. They hold also where a managed
  configuration allows only its own hooks (a company machine), and there they are the guard.
- **No escape hatches**: no permission that runs an interpreter with any argument; only the precise tests and tools.
- **A way back**: the repository in git; the owner's data stores with server-side versions and trash.
- The guardian checks the settings of every machine and repository against these layers.

### Code

- **Values in one place**: no numbers, times, paths or thresholds hard-coded; configuration holds them. A value that
  differs between machines comes from an environment variable, with its default in configuration. Configuration is
  validated at start-up: raw values are parsed into types, and every wrong key says what is allowed.
- **Clean and lean**: remove what is not needed (files, keys, sections), no dead code, no useless work (repeated reads,
  calls or queries, scans where a map is enough, queries without a time filter); the simplest form that does the job,
  no abstraction for a single use. Comments only for the non-obvious why, constraints, edge cases; never history dates.
- **Tested locally first**: every project with code has a `cicd/` folder with its deterministic checks (tests, syntax,
  alignment with configuration), run on the machine before every push by one shared runner. The remote CI runs the same
  steps, only where needed: a guard that must hold even if a machine is wrong (secrets scan, merge gate of a protected
  `main`), another operating system, or what costs nothing; never private rules, secrets or long paid jobs.
- **Testable**: logic in small pure functions, I/O at the edges; a test for every important behaviour (writes,
  idempotence, secrets) and every fixed bug; formats exchanged between projects have an example tested by both sides;
  end-to-end tests run against synthetic targets (sample applications, fake systems, made-up data), never real ones.
- **Design patterns where they help** (layers, adapters, configuration-driven behaviour), never over-engineered: they
  are how the owner reads and verifies code written by machines.
- **Observable**: every run leaves a result (what it did, counts, outcome) and logs that say what happened; an error is
  always visible and says what to do.
- **Reuse**: use what already exists; duplicated code goes to a common place; code useful to more than one project is
  a candidate for the shared product (its name in the guardian's data). A piece born in one product moves there when a
  second product wants it (the first expected: the updater from GitHub releases for desktop products).
- **PowerShell 7 (pwsh) everywhere**, the same on Windows and Linux; the only exception is a Windows first-run script,
  compatible with Windows PowerShell 5.1, which installs pwsh and stops. No absolute machine paths in scripts (relative
  to the script or from `$HOME`), no Windows-only commands without the alternative next to them.
- **Language**: English for identifiers, keys, file and folder names and commit messages; documentation, comments and
  logs follow the repository's own rules.
- No new feature without the owner's yes: ideas are proposals.

### Technologies and standards

- **Best of breed**: for every need, the standard or tool recognised as the best in its category, not an invented
  format: decisions as ADRs, architecture with arc42 and C4, quality with ISO 25010, acceptance criteria as
  Given/When/Then, in the reduced form the project needs. An exception (an own format, a less common tool) only with
  its reason written next to it; when the reason no longer holds, switch to the standard.
- Preferred languages: C#, bash and PowerShell 7; anything else only when needed, with the reason in the README.
- **Reproducible builds**: versions pinned in one place (packages, SDK, runtime, test runner, container images,
  Actions), warnings treated as errors, the recommended analysers on: the same result on every machine.
- Dependencies, tools and languages: open source under MIT or Apache 2.0, portable across Windows and Linux; another
  licence, or something that runs on one system only, only with the reason in the README.

### Coherence and consistency

- **Consistency, the form**: the same thing has the same shape everywhere (names, renamed everywhere in one change;
  README sections, statuses of ideas, file names, formats, commands with dry run and apply, results, logs, messages).
- **Coherence, the substance**: no two places say different things. Every fact has one source; the other places link
  to it. A contradiction (README against code, configuration against documentation, one project against another) is a
  finding: it is settled at the source, or written as an open question until the owner decides.
- **One system**: a new solution in one project holds for all of them, or the reason why not is written.
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

Brainstorming converges and empties: a session on a project starts from it and asks the owner every open question and
every proposed idea at once, each with a recommendation. An idea has one of three statuses (in an Italian repository:
proposta, accettata, scartata):

- `proposed`: still to examine, or waiting for something.
- `accepted`: decided and not yet realised. The row stays while the work is pending; its text may say where the work
  lives (a feature whose `spec.md` cites `IDEA-n`, a plan, a README section). Once realised (in an ADR, a README
  section, the norm, a feature, another project's brainstorming, the backlog) the row is removed; git keeps its
  history.
- `rejected: <reason>`: kept, so the same idea is not proposed again.

An idea that repeats another is folded into it. An **answered** question goes where it belongs and is removed.

A `proposed` idea, an `accepted` one without progress, or an open question left without an answer for long is a
finding of the guardian, brought to the
owner. What reaches the file is already clean: no personal data, customer data or employer data, whatever the
repository.

### README

Names and order as here; a section is omitted, never renamed; lists of ideas or things to do go to `brainstorming.md`.
Five fixed sections say what the project is: (1) `# <Name>` and one line, what it is; (2) Goal: why it exists, what
problem it solves, for whom, 1-3 lines; (3) Description: what it does and where it runs; (4) Technologies: languages,
runtimes, services, main versions, with the reason for anything not C#, bash or PowerShell; (5) Dependencies: table
`From | What it uses | Type` (project, library, service, machine) or "None", also who depends on it. Five more, only
when needed, say how to work on it: (6) Architecture: the folder tree (code block, one line per entry), components and
flows, a mermaid diagram only if needed; (7) Rules: the project's own, never the norm repeated; (8) Usage: installation,
commands, how to change and ship; (9) Tests: the `cicd/` steps and how to run them; (10) Agents: what runs in parallel
and who does it, contracts not to touch, what stays with the owner. In Italian: Obiettivo, Descrizione, Tecnologie,
Dipendenze, Architettura, Regole del progetto, Uso, Prove, Agenti.

### Working with agents

Roles, not models, so they hold with any assistant and do not age: which model fills each role is chosen in one place
by the guardian.

| Role | Does | Does not |
|---|---|---|
| Orchestrator | plan, contracts and interfaces (first, in series), decisions, wiring, build, tests, commits | mechanical work it can delegate |
| Executor | one task at a time, in an isolated worktree, in parallel with the others; touches only its files | build, commits, contract changes |
| Microtask | searches, test stubs from the criteria, renames, mechanical checks | decisions |
| Reviewer | a fresh agent: reads the diff with fresh eyes, runs the tests, checks the criteria | fixing things itself |

- **Deterministic work goes into tools, not into reasoning**: whatever is done the same way every time (checks,
  scaffolding, counting, formatting, syncing) becomes a script, kept in `tools/` with its usage written at the top;
  agents run the tools and keep for themselves only what needs judgment. A deterministic job done by hand twice
  becomes a tool.
- Independent work goes to agents at once, as many as the machine sustains (never two on a quota-limited API); only
  what touches different files runs in parallel, never two agents on the same file or task. Small jobs are done, not
  delegated.
- A new agent's prompt says everything (files to read, boundaries, what to report): it does not see the conversation.
  Every agent reports files changed, tests run and doubts; never "done" without saying what was verified.
- The orchestrator never calls work done on the agents' reports: it checks the contracts between their results, runs
  all the checks together and searches for old names, round after round until one finds nothing. An agent silent for
  long is asked for its state. Real data and production: the agent prepares, the owner approves and ships.
- **Unsupervised work**: the owner decides first (a converged brainstorming, criteria as tests), then the machine works
  alone on the working branch. A missing decision is never guessed: it becomes an open question in `brainstorming.md`,
  the owner is notified, and the work moves to a task that does not depend on it. A session has a limit (tasks or
  time) and stops when the same check fails twice in a row. It ends with a report (tasks done, checks run, open
  questions); the owner reads that, not the session, and orders push and merge.
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
- **Single-user products that work on Excel files**: the workbook is the source and the final format, a local
  database only a support for speed; import and export are validated and refuse the data when it does not match. Other
  products choose their data model themselves.

### Workflow

- `main` is protected, for everyone: it changes only through a pull request from `dev`, merged with a merge commit
  once CI is green (common rules, "Branches, and nothing else").
- Dependabot proposes towards `dev` (`target-branch: dev` in `.github/dependabot.yml`), never towards `main`; its
  `dependabot/*` branches are the only other branches allowed, while their pull request is open.
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
|   |-- settings.json            permissions of coding assistants (common rules, "Permissions of coding assistants")
|   \-- agents/                  executor.md, reviewer.md, microtask.md: role and tools only (when needed)
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
- An idea becomes work only with the owner's yes: it becomes a feature and leaves `brainstorming.md` (common rules,
  "Brainstorming"). `spec.md` and `plan.md` start with a `From:` line naming where they come from (`IDEA-n`, an ADR, a
  README section), so the guardian can trace every feature back. "Done when" points to the Given/When/Then criteria,
  so it is a passing test.
- A file is added when it is needed, not before. The README stays short and points to `specs/`.
- From the first code on, the product runs its own `cicd/` steps with `tools/ci.ps1`, the same runner the pull
  request CI uses: whoever clones it tests it as the owner does.

### Parallel work from the tasks

- Tasks are written to be parallel: each declares the files it touches and what it depends on. Two tasks with no
  shared files and no open dependencies run together, one executor each in its own worktree.
- Contracts and interfaces from `plan.md` come first, written by the orchestrator in series; no executor changes them.
- The reviewer checks the diff against the criteria in `spec.md`.
<!-- END product rules -->

## Beacon rules

None yet beyond the common rules. What the product is: `README.md`; what it must do: `specs/`.

## Verification

Commands the orchestrator runs before a commit:

- `pwsh -NoProfile -File cicd/run.ps1`: lint and all tests (steps in `cicd/README.md`).
- One test file: `Invoke-Pester -Path tests/<Name>.Tests.ps1 -Output Detailed`.
