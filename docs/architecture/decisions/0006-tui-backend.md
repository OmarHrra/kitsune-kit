# ADR 0006: Optional TUI backend

- Status: accepted
- Date: 2026-08-14

## Context

Kitsune Kit needs a full-screen terminal interface without making it necessary for automation or conventional CLI use. RatatuiRuby 1.5 provides excellent widgets and headless testing, but currently requires Ruby 3.2.9 or newer, distributes native platform artifacts, and is LGPL-3.0-or-later. Kitsune Kit currently supports the Ruby 3.2 series and must remain installable as one portable Ruby gem.

## Decision

- The domain emits presentation-neutral events.
- `Tui::Store`, `Tui::Renderer`, `Tui::Controller` and `Tui::Terminal` are separate components.
- The initial renderer uses a small ANSI terminal backend and a deterministic text buffer.
- Every TUI action invokes the same workflow used by the conventional CLI.
- A future RatatuiRuby backend may replace only renderer, input and terminal lifecycle components.
- The TUI remains optional at runtime; non-TTY use never initializes it.

## Consequences

The gem has no native TUI dependency and works completely through CLI/JSON. The initial widget set is intentionally smaller than RatatuiRuby, but its state, navigation, worker and snapshots remain reusable if a richer backend is adopted.
