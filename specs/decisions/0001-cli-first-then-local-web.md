# 1. Command line first, then a local web interface

Date: 30/10/2026

## Status

Accepted

## Context

IDEA-1 asked for a web interface; the open question was web or desktop. The map of the network (IDEA-2, IDEA-8) needs
a graphical view, but the first version has to answer one thing: where traffic stops. Beacon must also run inside a
container when that is the context (IDEA-6), where a desktop app cannot.

## Decision

The first version is a command line tool that runs the checks and writes a report. A web interface comes later,
served by Beacon itself on localhost, on top of the same engine. No desktop app.

## Consequences

- The engine and its results are independent of any interface: the command line and the web view read the same
  results.
- The map arrives with the web interface, not in the first version.
- The same binary works on a workstation, a server or a container; the web view is reached with a browser.
