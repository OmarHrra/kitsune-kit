# Configuration

Kitsune Kit configuration schema version 1 is YAML with a fixed structure. Unknown keys at any nesting level,
malformed sections and future schema versions are rejected instead of being ignored.

## Files and precedence

The base file is `.kitsune/config.yml`. The selected overlay is `.kitsune/environments/NAME.yml`. Values are combined in this order, with later sources winning:

1. built-in safe defaults;
2. `.kitsune/config.yml`;
3. `.kitsune/environments/NAME.yml`;
4. supported environment-variable overrides;
5. explicit overrides supplied by the internal API.

Environment selection itself uses:

1. `--env NAME`;
2. `KITSUNE_ENV`;
3. `.kitsune/environment`;
4. `development`.

Names start with a lowercase letter or digit and may then contain lowercase letters, numbers, `_` and `-`; uppercase names and path traversal are rejected so Compose project identity remains stable.

Use:

```bash
kit env list
kit env current
kit env use production
```

## Complete schema

```yaml
version: 1

provider:
  name: digitalocean
  token_env: DO_API_TOKEN

server:
  name: myapp-production
  region: sfo3
  size: s-1vcpu-1gb
  image: ubuntu-24-04-x64
  ssh_key_id: "12345678"
  tags:
    - kitsune-managed

ssh:
  user: deploy
  port: 22
  key_path: ~/.ssh/id_ed25519
  allowed_cidrs:
    - 203.0.113.10/32

services:
  postgres:
    enabled: false
    mode: managed
    host:
    image: postgres:17
    publish: false
    bind: 127.0.0.1
    allowed_cidrs: []
    port: 5432
    password_env: POSTGRES_PASSWORD
  redis:
    enabled: false
    mode: managed
    host:
    image: redis:7.2
    publish: false
    bind: 127.0.0.1
    allowed_cidrs: []
    port: 6379
    password_env: REDIS_PASSWORD

system:
  swap_size_gb: 2
  swap_swappiness: 10
  unattended_upgrades: true
  metrics: false
  metrics_installer_sha256:

dns:
  domains: []
  ttl: 3600
```

## Field reference

### `provider`

| Field | Meaning |
| --- | --- |
| `name` | Must currently be `digitalocean`. |
| `token_env` | Name of the environment variable containing the token. Must look like an uppercase environment-variable name. |

### `server`

| Field | Validation |
| --- | --- |
| `name` | Lowercase DNS-style resource name, 1–63 characters. |
| `region` | Non-empty DigitalOcean region slug. Provider validity is checked by the API. |
| `size` | Non-empty DigitalOcean size slug. |
| `image` | `ubuntu-22-04-x64` or `ubuntu-24-04-x64`. |
| `ssh_key_id` | ID of a public key already uploaded to DigitalOcean. |
| `tags` | Tags used to establish ownership. Keep `kitsune-managed`; a same-name untagged server is not adopted. |

Region/size/image differences are immutable in the current model. A plan reports replacement as destructive; Kitsune Kit never silently replaces the server.

### `ssh`

| Field | Validation |
| --- | --- |
| `user` | Linux username: lowercase letters/numbers plus `_`/`-`, maximum 32 characters. |
| `port` | Integer from 1 through 65535. |
| `key_path` | Expanded local path to an existing regular private-key file with mode `0600` or stricter. |
| `allowed_cidrs` | Valid IPv4 or IPv6 CIDRs permitted through UFW. Empty means the SSH port is not CIDR-restricted by this list. |

SSH policy is ordered to keep a verified path open: create/verify the deploy user, install and validate the new policy, open the new firewall route, then remove obsolete managed rules.

### `services.postgres` and `services.redis`

| Field | Meaning |
| --- | --- |
| `enabled` | Include the service in the desired plan. |
| `mode` | `managed` installs on the VPS; `external` records an endpoint and forbids local lifecycle actions. |
| `host` | Required hostname/IP for `external`; must be empty for `managed`. |
| `image` | Valid Docker image reference. Pin a digest for stronger reproducibility. |
| `publish` | Publish a host port. Defaults to false. |
| `bind` | IPv4 bind address used only when publishing. |
| `allowed_cidrs` | Required and non-empty when `publish` is true. |
| `port` | Host port, 1–65535. Container ports remain 5432/6379. |
| `password_env` | Environment-variable name containing the required secret. |

Images, binds, ports and secret names reject newline/shell/YAML injection patterns before any SSH connection is opened.

External example:

```yaml
services:
  postgres:
    enabled: true
    mode: external
    host: db.internal.example
    port: 5432
    publish: false
```

External mode is metadata and a safety boundary, not a database-provisioning integration. `kit service postgres
status` reports the endpoint without its secret. Install, backup, remove and destroy-data refuse to act; manage
availability, TLS, backups and destruction with the external provider. External services never add Docker,
firewall or private-port checks to the VPS plan.

### `system`

| Field | Validation |
| --- | --- |
| `swap_size_gb` | Integer 0–64. Zero disables swap managed by Kitsune Kit. |
| `swap_swappiness` | Integer 0–100. |
| `unattended_upgrades` | Boolean. |
| `metrics` | Boolean; false by default. |
| `metrics_installer_sha256` | Required lowercase 64-character SHA256 when metrics is enabled. |

Kitsune Kit downloads the DigitalOcean metrics installer to a file, verifies the configured digest and only then executes it. Re-verify the digest whenever the upstream installer changes.

### `dns`

| Field | Validation |
| --- | --- |
| `domains` | Valid hostnames. Public Suffix List parsing determines the provider zone and record name. |
| `ttl` | Integer 30–86400 seconds. |

Each created/updated record is persisted immediately, including its previous value, so a partially failed run can resume and rollback safely.

## Supported environment-variable overrides

| Variable | Field |
| --- | --- |
| `KITSUNE_PROVIDER` | `provider.name` |
| `KITSUNE_SERVER_NAME` | `server.name` |
| `KITSUNE_REGION` | `server.region` |
| `KITSUNE_SIZE` | `server.size` |
| `KITSUNE_IMAGE` | `server.image` |
| `KITSUNE_SSH_KEY_ID` | `server.ssh_key_id` |
| `KITSUNE_SSH_USER` | `ssh.user` |
| `KITSUNE_SSH_PORT` | `ssh.port` |
| `KITSUNE_SSH_KEY_PATH` | `ssh.key_path` |
| `KITSUNE_METRICS_INSTALLER_SHA256` | `system.metrics_installer_sha256` |

Secrets are indirect: `provider.token_env` and each `password_env` name which environment variable Kitsune Kit reads. Their values are registered with the redactor and never written to state.
Enabled services require at least 12 bytes and reject empty values and common defaults such as `password`, `postgres`, `redis`, `changeme` and `secret` before any provider or SSH request.

## Schema evolution

Version 1 is the direct-rewrite baseline and has no supported predecessor to migrate: the old preview `.env`
format is intentionally not interpreted. A future schema change must ship an explicit, tested `N -> N+1`
migrator that preserves a backup before changing configuration or state. Kitsune Kit never guesses at an unknown
version. Until such a migrator exists, open the project with a compatible Kitsune Kit version and follow that
release's documented migration path; never copy provider IDs by hand.

JSON/event consumers must reject unknown `schema_version` values while tolerating documented additive fields
within a supported version. Breaking adapter signatures increment `Adapters::API_VERSION`.

## State is not configuration

`.kitsune/state/ENV.json` is Kitsune Kit's ownership journal. Do not edit it manually or commit it. Writes use a per-environment lock, atomic rename and `.backup` copy. Losing state removes Kitsune Kit's proof of ownership; it intentionally refuses destructive actions rather than guessing by name.
