# Network Reciprocity Web Calculator

## Goal

Build a local-first web calculator for the heterogeneous network reciprocity
critical condition. The Julia code is the source of truth for the mathematical
model; the web UI is only an input/output layer.

## Directory Rules

- `AGENTS.md`: global collaboration rules. Do not edit unless the user asks.
- `CLAUDE.md`: project-specific rules and workflow.
- `Initial program/`: original reference code from the user. Do not edit unless
  the user explicitly asks for changes to the original file.
- `src/`: Julia module code used by tests, scripts, and the future web API.
- `test/`: Julia tests for mathematical and input-validation behavior.
- `examples/`: small reproducible examples that can be run from the command line.
- `server/`: future Julia HTTP API for the local web app.
- `web/`: future browser UI.
- `docs/`: short design notes and model/input conventions.
- `Dockerfile`, `.dockerignore`, `render.yaml`: Render free-tier deployment
  configuration for the public web calculator.

## Development Order

1. Keep the core Julia calculation testable before adding UI code.
2. Add or update tests before changing formulas or indexing logic.
3. Preserve the original research code until the refactored module has matching
   behavior on agreed examples.
4. Treat formula changes as research changes: state the assumption, add a
   verification case, then edit.

## Validation

Primary validation command:

```powershell
julia --project=. -e "using Pkg; Pkg.test()"
```

Current environment note: if `julia` is not available in `PATH`, tests cannot be
run from this workspace until Julia is installed or its executable path is added.

## Web MVP Scope

The first web version should be a local calculator:

- Input a symmetric weighted adjacency matrix; the API may convert it to the
  bidirectional edge list required by the Julia core.
- Input `PTE` and decision-mechanism values `mu`. The browser may accept `∞`
  for random trial-and-error and convert it to negative `mu`, matching the
  Julia convention for μ_i → ∞.
- Keep the response function out of the main UI. Use the original local
  defaults `g(0) = 0.5` and `g'(0) = 1.0` unless a research change explicitly
  asks to expose or alter them.
- Compute `bc_star`, `kappa`, `pi`, convergence status, and error.
- Show user-facing result names such as `Critical b/c`; keep raw numerical
  diagnostics out of the main output unless they help interpret the result.

Do not add authentication, databases, or cloud services beyond the documented
Render demo deployment unless the user explicitly asks.
