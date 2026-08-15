# Security model

Kitsune Kit changes remote security policy and can destroy infrastructure. Its design favors explicit ownership, verified transitions and refusal over implicit adoption.

## Trust boundaries

Kitsune Kit trusts:

- the local machine/user running the gem;
- configuration committed by the project;
- secrets supplied through the process environment;
- the independently verified first SSH host-key fingerprint;
- provider and package repositories over TLS;
- local state as the record of which resources Kitsune Kit owns.

Compromise of the local account, repository, environment, private key or state can invalidate these assumptions. Kitsune Kit is not a secrets vault and does not encrypt local files.

## Secrets

Never place API tokens or service passwords in YAML, command arguments, state or Git. Configuration stores only environment-variable names. Secret values are registered with a central redactor before event reporting/logging.

```bash
export DO_API_TOKEN="..."
export POSTGRES_PASSWORD="..."
export REDIS_PASSWORD="..."
```

Generated service `.env` files exist only on the remote server with mode `0600`. Compose output, fingerprints and local state do not contain plaintext passwords. Newlines, carriage returns and NUL bytes are rejected.

Process environments may be observable by privileged local processes and CI administrators. Use the secret store of your CI platform, limit token scope, rotate credentials and avoid shell tracing.

## SSH

Kitsune Kit never uses `verify_host_key: :never` in production adapters. A new key raises a prompt containing the exact SHA256 fingerprint. Acceptance records it in `.kitsune/known_hosts`; later sessions use strict matching.

`--trust-host-key` accepts only an exact fingerprint and is intended for independently verified non-interactive bootstrap. A mismatch fails. Key changes are not automatically accepted.

SSH hardening preserves a recovery route:

1. bootstrap using deploy or root access;
2. create/configure the deploy user;
3. verify a second deploy-user connection;
4. validate generated `sshd_config` with `sshd -t`;
5. reload first with key-based root recovery still enabled;
6. verify a new deploy-user connection, then disable root and verify again;
7. add the new firewall route before removing a stale route owned by Kitsune Kit and verify deploy access once more.

The transport keeps the already authenticated session open across each safety-critical transition. Fresh verification uses a separate connection; if it fails before or after finalization, the preserved session runs the script rollback before it closes. A recovery failure is surfaced as a verification error with provider-console guidance. Kitsune Kit does not modify unrelated SSH/firewall configuration during rollback.

## Command and file safety

Remote commands are a validated executable plus separately Shellwords-escaped arguments. File uploads are base64 data over stdin, not interpolated shell source. Absolute remote paths and modes are validated before connecting.

Generated Compose documents are built as Ruby hashes and serialized with YAML. Resource names, users, ports, CIDRs, images, domains and environment names have allow-list validation. Tests include metacharacters, substitutions, traversal and embedded newline attacks.

Versioned shell scripts use `set -Eeuo pipefail`, explicit action dispatch and verification. ShellCheck runs in CI.

## Firewall and data services

PostgreSQL and Redis do not publish host ports by default. When publishing is enabled:

- at least one valid allowed CIDR is required;
- Compose binds only the configured IPv4 address/port;
- matching allow and terminal drop rules are installed in Docker's `DOCKER-USER` chain because Docker-published ports can bypass UFW forwarding policy;
- only rules recorded as created by Kitsune Kit are reconciled or removed.

Use private networking or an application-local Docker network whenever possible. Never publish a database to `0.0.0.0` with a broad CIDR unless the exposure is deliberate and independently audited.

## Ownership and destructive actions

Kitsune Kit records provider IDs, DNS record IDs, remote fingerprints, file backups and firewall ownership. Same-name resources without the expected tags/state are not adopted or deleted.

Semantics:

| Operation | Server | Containers | Data volume | Configuration |
| --- | --- | --- | --- | --- |
| `rollback` | Keep | Restore/remove managed | Keep | Restore captured state |
| service `remove` | Keep | Remove | Keep | Keep ownership record |
| service `destroy-data` | Keep | Remove | Delete | Delete managed service files/state |
| server `destroy` | Delete | Delete with server | Delete with server | Restore/remove managed DNS after provider deletion |

`--yes` never authorizes permanent service data or server destruction. Exact confirmation strings are required.
Interactive service-data destruction offers a restricted archive first. In automation,
`--backup-before-destroy` requests it explicitly; copy that same-server archive to independent storage.

The deploy user belongs to the `docker` group and has passwordless sudo, so it is effectively a privileged
administrator. Protect its private key as a root credential, restrict SSH CIDRs where possible and rotate the
key after suspected exposure.

## State, logs and diagnostics

State/log/support directories and files use restrictive permissions. State writes use file locks, fsync, atomic rename and backups. Logs are structured, redacted and rotated. Support bundles are local JSON and never transmitted.

Back up `.kitsune/state/` securely. If state is lost, recover it rather than recreating ownership from names. Inspect support bundles before sharing; redaction is defense in depth, not proof that arbitrary user-provided text contains no sensitive information.

When both state copies are lost, `kit server import` is the limited recovery path. It requires an exact numeric provider ID and exact-name confirmation, verifies the complete configured server identity, and imports only server metadata. It deliberately does not claim remote resources or DNS records.

## Supply chain

- Docker is installed from Docker's official signed apt repository.
- Metrics installation is off by default. Enabling it requires an explicitly configured SHA256 for the downloaded script; no `curl | sh` pipeline is used.
- Ruby dependencies are locked for development, audited with Bundler Audit and updated through Dependabot.
- Release metadata requires MFA on RubyGems. Releases should use trusted publishing and protected tags when configured.

Container service tags are mutable unless pinned by digest. For production reproducibility, use an image reference ending in `@sha256:...`, test it in staging and update deliberately.

The internal Alpine image used only to archive service volumes is multi-platform and pinned to the published Docker Official Image manifest digest. Its source is the [Docker Hub `alpine:3.20` manifest](https://hub.docker.com/layers/library/alpine/3.20/images/sha256-ac77ebc035f69184acb2660028580c9053f6d0f892de7933e1456d8b5e0ac085). Updating it requires reviewing the new manifest and running backup/restore tests.

Kitsune Kit contains no telemetry or automatic upload path. Logs and support bundles remain local unless the
operator deliberately shares them.

The latest manual review and its limitations are recorded in [Security audit](security-audit.md).

## Reporting vulnerabilities

Follow [SECURITY.md](../SECURITY.md). Do not include real credentials, addresses or domains in a public issue or reproduction.
