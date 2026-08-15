# ADR 0005: Plan, apply, rollback, remove and destroy semantics

- Status: accepted
- Date: 2026-08-14

## Decision

- `plan` observes and describes changes without mutation.
- `apply` converges actual state to desired state and verifies postconditions.
- `rollback` restores captured prior state when restoration is safe and supported.
- `remove` stops and removes a managed capability while preserving data.
- `destroy` permanently removes a provider resource.
- `destroy-data` permanently removes service data and is always separately confirmed.

Destructive operations show exact IDs and require the resource name as confirmation in an interactive terminal or an explicit confirmation option in non-interactive mode.

## Consequences

The word rollback is never used as a synonym for deleting a server or Docker volume. Operations that cannot restore prior state say so before execution.
