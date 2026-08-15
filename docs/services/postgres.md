# PostgreSQL service

PostgreSQL is an optional Docker Compose service managed by Kitsune Kit on the target server. It is disabled and private by default.

## Enable

```yaml
services:
  postgres:
    enabled: true
    image: postgres:17
    publish: false
    bind: 127.0.0.1
    allowed_cidrs: []
    port: 5432
    password_env: POSTGRES_PASSWORD
```

```bash
export POSTGRES_PASSWORD="$(ruby -rsecurerandom -e 'print SecureRandom.base64(36)')"
kit plan
kit service postgres install
```

The Compose project is `kitsune-ENV-postgres`, attached to the external `kitsune-private` network. Data is stored in its named `data` volume. The database name is `app_ENV` with `-` converted to `_`; the user is `postgres`.

## Connectivity

With `publish: false`, there is no host port mapping. Applications on `kitsune-private` can connect using Docker service/network addressing and the configured credentials.

Publishing is an explicit exception:

```yaml
publish: true
bind: 0.0.0.0
allowed_cidrs:
  - 203.0.113.10/32
```

Kitsune Kit requires at least one CIDR and installs owned `DOCKER-USER` allow/drop rules. Validate the result externally; UFW alone does not reliably restrict Docker-published ports.

## Status, backup and removal

```bash
kit service postgres status
kit service postgres backup
kit service postgres remove --yes
```

Backup pauses the service, archives the named volume into a restricted remote backup directory and unpauses in an `ensure` path. The returned path is on the server. Copy it to independent storage and test restoration; creating an archive on the same Droplet is not disaster recovery.

`remove` runs Compose down without `--volumes`, removes only firewall rules owned by Kitsune Kit and marks the service removed. Data remains.

## Permanent destruction

```bash
kit service postgres backup
kit service postgres destroy-data --backup-before-destroy --confirm-destroy postgres@production
```

In an interactive terminal, `destroy-data` offers to create the archive and then requires typing
`postgres@ENV`. Automation uses `--backup-before-destroy` when desired and must always provide the exact
`--confirm-destroy` value. The data archive is retained, while Compose volumes, managed configuration
backups/files, markers and service state are removed. Copy the archive off the server before relying on it;
`--yes` cannot replace the exact confirmation.

## Updates and rollback

Changing the image/configuration/secret changes the service fingerprint. Before an update, Kitsune Kit backs up managed Compose/env files. It validates Compose, waits for health, reconciles firewall rules and only then records the new state. Failed updates restore previous files and restart the prior service where possible.

`kit rollback` restores captured managed configuration and preserves the volume. It does not promise database-level downgrade compatibility; test image upgrades and rollback in staging.

## External PostgreSQL

Set `enabled: true`, `mode: external`, `host` and `port` to represent a provider-managed database without
installing it on the VPS. `kit service postgres status` reports the endpoint; install, backup, remove and
destroy-data are intentionally unavailable. Kitsune Kit does not test provider TLS, create users/databases or
manage external backups. Supply those through the database provider and application deployment system.
