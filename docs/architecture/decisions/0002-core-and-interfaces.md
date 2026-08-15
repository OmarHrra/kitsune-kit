# ADR 0002: One core with CLI, JSON and TUI presentations

- Status: accepted
- Date: 2026-08-14

## Context

Kitsune Kit must be pleasant interactively and fully usable in scripts and CI. A full-screen TUI is valuable for inspecting resources and following long operations, but cannot become a second infrastructure implementation.

## Decision

Application workflows depend only on ports for provider, transport, state, secrets, clock and event publishing. They never call Thor, `puts`, terminal widgets or concrete adapters.

Workflows publish typed events. Human CLI output, JSON output, logs and the TUI consume the same event stream. Every TUI action has a documented CLI equivalent. The complete lifecycle works without installing or opening the TUI.

The first TUI renderer will be isolated behind a presentation interface. A native rendering dependency may be adopted later without changing workflows.

## Consequences

- CLI and TUI parity is testable at the workflow-result level.
- CI can use `--format json` and `--no-input`.
- TUI failures cannot change domain semantics.
- Presentation differences are limited to navigation, prompts and progress rendering.
