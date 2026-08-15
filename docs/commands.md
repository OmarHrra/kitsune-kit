# Command reference

The authoritative runtime reference is `kit help`, `kit help COMMAND` and the equivalent `kit COMMAND help`.
This document explains the semantics and automation contract that short help cannot capture.

## Global options

Global options may be passed to infrastructure commands:

| Option | Meaning |
| --- | --- |
| `-e`, `--env NAME` | Select an environment for this invocation. |
| `--root PATH` | Project root containing `.kitsune/`. Defaults to the current directory. |
| `--config PATH` | Use an alternative base configuration file. |
| `--format human|json` | Select human or versioned machine output. |
| `--no-color` | Disable ANSI styling. `NO_COLOR` is also respected by the entrypoint environment. |
| `--no-input` | Never prompt; fail with an actionable error when confirmation is required. |
| `--yes` | Approve reviewed, non-destructive changes. It never confirms permanent data/server destruction. |
| `--dry-run` | Build/display the plan without applying it. |
| `--quiet` | Limit human output to important findings and summaries. |
| `--verbose` | Include additional domain-event detail. |
| `--debug` | Include technical context/stack information for failures. |
| `--log` / `--no-log` | Enable/disable restricted redacted local logs. Enabled by default. |
| `--timeout SECONDS` | Upper bound for each remote step, provider HTTP request and readiness wait; must be positive. |
| `--trust-host-key SHA256:...` | Trust only this exact first-seen SSH fingerprint. |

## Core workflow

### `kit init [--force]`

Creates `.kitsune/config.yml`, a development overlay and environment selection. Existing generated files cause exit 9 unless `--force` is explicit. It also appends runtime artifacts to `.gitignore`.

### `kit doctor`

Read-only checks include Ruby/runtime, configuration, SSH-key permissions, security defaults, provider credentials, state schema, exact server ownership, verified SSH access, Ubuntu version, passwordless sudo, Docker/Compose, listening ports and managed drift.

Statuses are `pass`, `warn`, or `fail`. Warnings do not make the command fail; any failed check returns exit 1.

### `kit plan`

Calculates changes without mutation. Details exclude provider key IDs and secrets. Actions are `create`, `update`, `delete` and `no_change`; plans flag destructive changes.

### `kit apply`

Builds a fresh plan, displays it, rejects destructive replacement and asks for confirmation. `--yes --no-input` is the automation form. `--dry-run` guarantees no mutation.

Every run and step is journaled. The provider ID is saved immediately after server creation; remote markers and local state are saved after verified operations.
Human output ends with the redacted local log path and a post-apply `doctor`/zero-change-plan next step. Failed or
cancelled applies report the last confirmed step, run ID and exact `kit resume RUN_ID` command. JSON carries the
same guidance as a `warning_emitted` event and never receives an extra human-output line.

### `kit resume [RUN_ID]`

Resumes the named run or latest incomplete run. It rejects successful runs and saved operation sets that no longer match configuration. Completed steps are skipped. Confirmation is required (`--yes` in automation).

### `kit status`

Displays the selected environment, exact provider server and locally tracked resources. It does not run remote diagnostics; use `doctor` for that.

### `kit rollback`

Runs rollback in reverse dependency order for resources recorded as managed. It preserves the Droplet and service data volumes. It is not a universal snapshot restore: provider resources or pre-existing files that Kitsune Kit never owned are not touched.

## Server

```text
kit server show
kit server status
kit server create
kit server configure
kit server ssh
kit server import --provider-id DROPLET_ID --confirm-import SERVER_NAME
kit server destroy --confirm-destroy SERVER_NAME
```

- `show`/`status`: inspect server and state.
- `create`: apply only the server operation.
- `configure`: apply remote, service and DNS operations after the server operation.
- `ssh`: verify the managed connection, then replace the process with the system `ssh` client using strict known-host checking.
- `import`: recover only the server identity after state loss. It requires an exact numeric Droplet ID and configured server-name confirmation, then verifies name, tags, region, size, image, active status and public IP. It never imports remote-resource ownership.
- `destroy`: delete only the exact recorded provider ID after verifying name/tags, then restore/remove managed DNS and clear state. If provider deletion fails, DNS is left untouched; if DNS cleanup fails afterward, retrying completes cleanup without deleting a second server. It never deletes by name alone.

Interactive destruction asks the operator to type the exact server name. Automation must use `--confirm-destroy SERVER_NAME`; `--yes` is insufficient.
Before an interactive confirmation, Kitsune Kit prints the environment, provider, resource, recorded provider ID and recoverability. JSON confirmation errors include the same safe target context.

## Docker

```text
kit docker status
kit docker install
kit docker uninstall --yes
```

Uninstall refuses to run while managed services remain. Docker installation uses the official apt repository and creates the `kitsune-private` network.

## Services

```text
kit service postgres status
kit service postgres install
kit service postgres backup
kit service postgres remove --yes
kit service postgres destroy-data --backup-before-destroy --confirm-destroy postgres@ENV
```

Replace `postgres` with `redis` for Redis.

- `install`: service must be enabled and its secret environment variable present.
- `backup`: pauses the service, creates a restricted tar archive of the volume on the server and always unpauses it.
- `remove`: removes containers/network attachment and firewall rules owned by Kitsune Kit, but keeps the volume and managed files needed for recovery.
- `destroy-data`: optionally creates a restricted data archive, then removes containers, volume, owned
  configuration backups/files and state. In an interactive terminal it offers the backup and requires typing
  `TYPE@ENV`; automation can request it with `--backup-before-destroy` and must supply `--confirm-destroy`.
  The data archive is retained outside the service directory, but must be copied to independent storage.

When an enabled service has `mode: external`, `status` returns only its configured host/port and
`managed: false`. All local lifecycle actions fail safely; Kitsune Kit never treats an external provider's data as
a VPS Docker volume.

## DNS

```text
kit dns list
kit dns plan
kit dns apply
kit dns remove --yes
```

DNS operations use exact record IDs and store original values. `remove` restores updated records and deletes only records created by Kitsune Kit.

## Environments

```text
kit env list
kit env current
kit env use NAME
```

`use` validates that `.kitsune/environments/NAME.yml` exists and writes the selection atomically. An explicit `--env`/`KITSUNE_ENV` wins without changing the persisted selection.

## Support

```bash
kit support bundle
```

The human-readable command prints the complete redacted bundle after writing it, so it can be reviewed before
sharing. JSON mode returns the local path without adding non-JSON output. Kitsune Kit never uploads the bundle.

Creates a permission-restricted JSON file under `.kitsune/support/` with versions, platform, redacted configuration/state, doctor results and selected redacted logs. The path is printed; Kitsune Kit never uploads it. Inspect it before sharing.

## TUI

`kit ui` starts the optional full-screen interface. Bare `kit` does the same only with interactive stdin/stdout; otherwise it prints help. See [TUI](tui.md).

## Version

`kit version`, `kit --version` and `kit -v` print the installed Kitsune Kit version without loading project configuration or contacting a provider.

## JSON output

Successful workflow documents use schema version 1 and include:

```json
{
  "schema_version": 1,
  "command": "plan",
  "environment": "production",
  "run_id": "...",
  "status": "success",
  "duration_ms": 12,
  "result": {},
  "warnings": [],
  "events": []
}
```

Errors are JSON on standard error:

```json
{
  "schema_version": 1,
  "status": "failure",
  "error": {
    "code": "configuration_error",
    "message": "...",
    "hint": "...",
    "context": {}
  }
}
```

Treat unknown additive keys as forward-compatible, but reject unsupported `schema_version` values in consumers.

## Exit codes

| Code | Meaning |
| ---: | --- |
| 0 | Success, including a no-change plan/apply. |
| 1 | Unexpected failure or failed `doctor` check. |
| 2 | Invalid CLI syntax/unknown command. |
| 3 | Invalid/missing configuration or unsupported environment. |
| 4 | Authentication failure. |
| 5 | Provider API failure. |
| 6 | SSH/network connection failure. |
| 7 | Remote command failure. |
| 8 | Post-change verification failure. |
| 9 | Unsafe operation or missing confirmation. |
| 10 | Timeout. |
| 130 | Interrupted by `SIGINT`. |
