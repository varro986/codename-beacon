# 3. Run result: JSON per check, table on the console

Date: 30/10/2026

## Status

Accepted

## Context

The earlier scripts mixed machine-readable lines (group, target, check, tool, status, detail) into a human log and
parsed them back; history was copied by hand into tables. The command line comes first and a web view later
(ADR 0001); both, and the history of runs, need the same results.

## Decision

- Every run writes its own folder, named by its start time, with a JSON result file and the raw log.
- The result file holds the run (start, end, egress identity, complete or partial) and one record per check: group,
  target, check, status (`OK`, `WARN`, `FAIL`, `SKIP`, `INFO`), detail, timings.
- The console shows a coloured table with totals per group and per target.
- Other formats (spreadsheet, HTML) are generated from the JSON, never in its place.

## Consequences

- The command line, the web view and the comparison between runs read one format, with a tested example.
- A run that does not end is recognisable as partial.
- Exporting to a spreadsheet (IDEA-7) is a reader of the JSON, not a second source.
