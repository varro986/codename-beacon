# cicd

The product's local checks, run on the machine before every push: `pwsh -NoProfile -File cicd/run.ps1`.

1. **lint**: PSScriptAnalyzer on `src/`, `tests/` and `cicd/`, warnings and errors (`PSScriptAnalyzerSettings.psd1`).
2. **tests**: Pester on `tests/`, contracts included (the examples against their schema).

Tools: Pester 5.5 or later, PSScriptAnalyzer 1.21 or later; `-InstallTools` installs the missing ones for the current
user. The remote CI (`.github/workflows/cicd.yml`) runs the same script on pull requests, on Linux and Windows.
