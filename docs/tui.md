# Optional terminal interface

The TUI is a full-screen convenience layer. It is not required to install or use Kitsune Kit, and it contains no provider, SSH or infrastructure logic.

```text
kit                    Open the TUI only when stdin/stdout are interactive
kit ui                 Request the TUI explicitly
kit plan               Conventional CLI, always available
kit apply --no-input   Conventional non-interactive CLI
```

When no TTY is available, bare `kit` prints help and `kit ui` returns a stable configuration error without writing alternate-screen escape sequences.

## Screens

- Dashboard: environment, server/managed resources and recent operations.
- Plan: exact domain plan used by `kit plan`/`kit apply`.
- Doctor: checks and actionable hints.
- Logs: bounded, redacted event feedback.
- Help and confirmation modals.

Minimum usable terminal size is 70 columns by 18 rows. Smaller terminals show a resize message rather than corrupting layout.

## Keys

| Key | Action | CLI equivalent |
| --- | --- | --- |
| `j`/`k`, arrows | Select resource | presentation only |
| `Tab` | Cycle screens | presentation only |
| `PgUp`/`PgDn` | Scroll logs | presentation only |
| `p` | Build/show plan | `kit plan` |
| `a` | Confirm and apply visible/fresh plan | `kit apply` |
| `d` | Run diagnostics | `kit doctor` |
| `r` | Confirm and resume latest run | `kit resume` |
| `l` | Show event logs | local log/output |
| `?` | Toggle help | `kit help` |
| `q` | Quit (confirmation while busy) | process exit |
| `Ctrl+C` | Request cooperative cancellation; quit when idle | `SIGINT` |

Apply/resume run in a worker thread so redraw/input remain responsive. Cancellation is cooperative between operations; the current remote command is still bounded by its timeout. After cancellation, a new token is used for the next action.

## Functional parity

The TUI's action object calls `InspectEnvironment`, `BuildPlan`, `Doctor` and `ApplyPlan` directly—the same workflows as the CLI. It cannot expose an infrastructure capability that lacks a conventional command. Technical/rare commands may remain CLI-only.

Automated tests assert that CLI/TUI-facing planning returns the same `Plan#to_h`. Differences are limited to navigation, confirmation and rendering.

## Implementation and testing

The initial backend is pure Ruby:

- `Tui::Store` converts domain events into immutable view state;
- `Tui::Renderer` turns state into a deterministic text buffer;
- `Tui::Controller` maps keys/modals/workers to shared actions;
- `Tui::Terminal` owns raw mode, alternate screen, resize and restoration.

Terminal restoration runs in `ensure`, including exceptions and `Ctrl+C`. Headless tests use fake terminals/events and snapshots; no real interactive terminal is needed. A future RatatuiRuby renderer can replace terminal/rendering components without changing the core or making the TUI mandatory.
