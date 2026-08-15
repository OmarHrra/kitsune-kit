# Compose customization

Kitsune Kit can manage PostgreSQL and Redis with a generated Compose document, a user overlay, or a complete
custom document. All three modes use the same `plan`, `apply`, state, recovery, rollback and data-safety workflow.
The TUI is optional; these features are fully available through ordinary CLI commands.

## Choosing a mode

| Mode | Kitsune Kit generates the base | Your file | Best use |
| --- | --- | --- | --- |
| `generated` | Yes | None | Secure defaults with image, port and password settings controlled by `config.yml`. |
| `overlay` | Yes | Compose override | Add labels, resource limits, logging, environment options or other supported overrides. |
| `custom` | No | Complete Compose document | Take direct ownership of the service definition while retaining Kitsune Kit lifecycle management. |

Start with `generated`. Prefer `overlay` while the base service, volume, network and health check still fit. Use
`custom` when you need to replace those assumptions. There is no legacy-blueprint compatibility layer.

## Generated mode

```yaml
services:
  postgres:
    compose:
      mode: generated
      file:
      allow_unsafe: false
```

The generated document is deterministic. Passwords appear only as `${POSTGRES_PASSWORD}` or
`${REDIS_PASSWORD}` references; their values are uploaded separately in a mode-`0600` `.env` file.

## Overlay mode

Create a project file such as `.kitsune/compose/postgres.override.yml`:

```yaml
services:
  postgres:
    environment:
      LOG_STATEMENT: ddl
    logging:
      options:
        max-size: 20m
        max-file: "5"
    deploy:
      resources:
        limits:
          memory: 1G
```

Reference it from configuration:

```yaml
services:
  postgres:
    compose:
      mode: overlay
      file: .kitsune/compose/postgres.override.yml
      allow_unsafe: false
```

Kitsune Kit uploads `compose.yml` followed by `compose.override.yml` and supplies both to every Docker Compose
command in that order. Changes to either document change the plan fingerprint.

## Custom mode and eject

Create a complete starting document automatically:

```bash
kit service postgres compose eject
```

This operation:

1. writes `.kitsune/compose/postgres.yml` from the current generated definition;
2. copies `.kitsune/config.yml` to `.kitsune/config.yml.backup`;
3. changes the service to `compose.mode: custom` and references the new file.

Existing output or backup files are not overwritten. Review both and use `--force` only when replacement is
intentional. YAML comments in `config.yml` may be reformatted by ejection; the byte-for-byte backup is retained.

A custom PostgreSQL file must contain `services.postgres`; Redis must contain `services.redis`. Configuration
fields such as `image` no longer alter a custom document, but `password_env`, publication/firewall policy and
lifecycle state remain part of Kitsune Kit's safety model.

## Inspecting and validating

```bash
kit service postgres compose show
kit service postgres compose validate
kit service postgres compose diff
kit service postgres compose show --format json
```

- `show` displays the exact ordered documents and their sources.
- `validate` parses YAML, validates the required service and applies local security policy.
- `diff` compares desired content with the last successfully applied Compose fingerprint.
- `plan` includes mode, ordered files, findings and the overall service fingerprint.
- `apply` uploads restricted files and runs `docker compose config --quiet` remotely before `up`.

Local validation does not replace Docker's own validation. A customization can pass local checks but fail because
an option is unsupported by the Docker Compose version on the VPS; `apply` then recovers the previous managed
files and attempts to restart the previous file set.

## File boundary

Customization files must:

- be inside `--root` after path expansion and resolution;
- be regular files, not symlinks;
- be at most 256 KiB;
- contain a top-level YAML mapping;
- avoid YAML aliases.

These constraints keep the deployment input reviewable and prevent a project configuration from reading an
arbitrary local file.

## Secrets

Never put a secret value in Compose YAML. Sensitive mapping keys and `KEY=value` environment-list entries are
rejected unless the value is a `${VARIABLE_NAME}` reference.

```yaml
services:
  postgres:
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
```

Export the variable before `doctor`, `plan`, `apply` or `install`. Compose display/JSON output never resolves its
value. The remote `.env`, Compose documents and backups use restricted permissions.

## Unsafe options

The local policy flags options that cross Kitsune Kit's normal isolation boundary, including:

- privileged containers and host PID/IPC/network namespaces;
- `ALL`, `SYS_ADMIN`, `SYS_PTRACE` or `NET_ADMIN` capabilities;
- host devices, absolute bind mounts and the Docker socket;
- ports outside the exact configured bind/port/firewall model;
- remote `build` contexts and unmanaged `env_file` references.

By default, any finding stops `show`, `validate`, `plan` and `apply`. If the configuration is intentionally outside
the standard boundary, review every finding and set:

```yaml
compose:
  mode: custom
  file: .kitsune/compose/postgres.yml
  allow_unsafe: true
```

This is an escape hatch, not a promise that Kitsune Kit manages or reverses the extra host resources. Findings
remain visible in metadata and plan details. Inline secrets are always rejected and cannot be enabled by
`allow_unsafe`.

## Rollback behavior

State records the mode, ordered filenames and content fingerprint after a verified apply. Before an update,
Kitsune Kit backs up all currently tracked and desired Compose files plus `.env`. A failed apply removes the new
file set, restores the backup and starts the prior ordered file set. `kit rollback` uses the same recorded set.

Docker volumes remain governed by the existing service contract: `remove` preserves data and `destroy-data`
requires exact confirmation. Compose customization does not broaden deletion ownership.
