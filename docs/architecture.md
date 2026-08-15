# Architecture

Kitsune Kit is a desired-state infrastructure tool with two replaceable presentation layers over one domain core.

```text
Conventional CLI ─┐
                  ├─ workflows ─ operations ─ provider / SSH / state / secrets
Optional TUI ─────┘       │
                          └─ domain events ─ human / JSON / TUI / run log
```

Presentation code does not create provider clients, open SSH connections or implement infrastructure rules. CLI and TUI call the same workflow objects and consume the same event stream.

## Layers

### Configuration and domain values

`Configuration` loads/merges typed schema values and validates them before adapters are constructed. `Change`, `Plan`, `Result`, typed errors and versioned events are presentation-neutral values.

### Workflows

Workflows coordinate use cases:

- initialize/select an environment;
- build/apply/resume a plan;
- inspect/doctor/rollback/destroy;
- generate support diagnostics.

They emit events but do not print. Apply uses `RunJournal` to record a compatible plan and step status for safe resume.

The event vocabulary includes run/plan start and finish, operation start/progress/success/failure/skip, and warnings. All subscribers receive the same versioned event values; progress currently guarantees operation boundary percentages and can become finer-grained without changing presentations.

### Operations

Each operation exposes a non-mutating `plan`, idempotent `apply` and, where meaningful, ownership-aware `rollback`. Operations include server creation, versioned remote scripts, services and DNS.

An operation verifies its result before writing a managed marker/state. Destructive replacement appears in the plan and is never applied implicitly.

### Ports and adapters

- `Provider`: server-spec validation, exact server/DNS lookup, create/wait/delete and credential validation.
- `Transport`: reachability, command execution with separate output/status/timing, and safe upload.
- `StateStores::Store`: read/update/delete and per-environment mutation-lock port; filesystem and in-memory fake adapters share a contract.
- `SecretStores::Store`: resolves secret values without adding them to domain configuration/state; environment
  and deterministic fake adapters execute the same contract.
- `Reporters::Reporter`: event-consumer port for human output, stable JSON, TUI state and redacted logs.
- `Clock`: UTC wall time, monotonic durations and sleeping, with a deterministic nonblocking fake.

Real DigitalOcean/Net::SSH adapters and deterministic fakes satisfy shared contracts. This permits full workflow failure injection without a VPS while reserving real behavior for integration/E2E suites.

The public adapter contract is versioned as `Kitsune::Kit::Adapters::API_VERSION`. See [Provider and transport adapters](architecture/provider-adapters.md).

## State and ownership

State schema version 1 contains environment, timestamps, resource identities, operation history and run journals. The server provider ID is recorded immediately after creation. DNS records are persisted one at a time. Remote resources carry script/config fingerprints and previous-state metadata.

State updates acquire a per-environment file lock, validate the whole document, preserve a backup, fsync a restricted temporary file and atomically rename it. Unsupported schemas/environment mismatches are rejected.

Names/tags help find resources, but provider IDs plus recorded ownership authorize destructive operations.

## Remote execution

Remote setup is stored in versioned Bash files under `lib/kitsune/kit/scripts`. `RemoteScript` fingerprints script bytes plus validated arguments, compares a remote marker, uploads through stdin-safe base64 transport, applies, verifies and records the marker.

SSH host verification is explicit. Commands and arguments are distinct at the transport boundary. Root and deploy transports are selected per operation; user bootstrap rollback deliberately uses root access.

Safety-critical SSH/firewall operations execute inside one preserved authenticated transport session while their postconditions are tested through separate fresh connections. The preserved session restores the captured policy if either fresh check fails.

## Services

`EnsureService` composes smaller collaborators for generated Compose YAML, file transaction/backups, firewall reconciliation, data backup and state transitions. Data lifecycle is deliberately separate from container/config lifecycle.

An enabled service in `external` mode is configuration metadata, not an operation. It is visible through the
CLI but excluded from VPS plans, Docker, firewall, doctor port checks and destructive lifecycle methods.

## TUI

The initial TUI is a pure-Ruby ANSI backend with deterministic renderer/store/controller boundaries. It has no native dependency and can be replaced without changing workflows. Headless tests feed events and keys into the store/controller and compare stable rendered buffers.

## Decisions

Detailed accepted decisions are in [architecture/decisions](architecture/decisions):

- product boundary and direct 0.5 rewrite;
- core/interface separation;
- configuration/state/secrets;
- supported platforms;
- operation semantics;
- optional TUI backend.
