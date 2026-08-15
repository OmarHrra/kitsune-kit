# Manual security audit

- Review date: 2026-08-14
- Scope: the `0.5.0` direct rewrite in this repository
- Method: manual source review plus static, unit, contract, integration and real DigitalOcean E2E gates
- Result: no unresolved critical, high or medium findings were identified in the reviewed scope

This is a maintainer security review, not a third-party penetration test or certification. Version 0.5.0 remains
pre-1.0 while hosted CI and timed usability acceptance complement the green real-infrastructure result.

## Threat model and boundaries reviewed

The review assumes the local operator account, project configuration, selected first-use SSH fingerprint and
provider account are trusted. It treats configuration values, remote output, provider responses, existing
same-name resources, terminal state and interruption timing as potentially hostile or inconsistent.

The following boundaries were inspected:

- YAML loading, schema/type validation, path normalization and environment precedence;
- secret acquisition, redaction, remote `.env` generation, logs, state and support bundles;
- provider authentication/error translation, exact IDs/tags and destructive ownership checks;
- SSH host-key handling, command argument escaping, uploads, deadlines and preserved-session recovery;
- user/sudoers, SSH policy, UFW, swap, unattended upgrades, Docker and metrics scripts;
- Compose generation, database exposure, `DOCKER-USER` ownership and data lifecycle;
- DNS zone parsing, exact record IDs, partial persistence and rollback;
- atomic state, locks, resumable journals, cancellation and terminal restoration;
- E2E credentials, TTL tags, cleanup filtering and release supply-chain configuration.

## Security properties verified in code and tests

### Input and command execution

Configuration uses safe YAML parsing and a closed nested schema. Resource names, environment names, users,
ports, CIDRs, domains, images, paths and secret-variable names are validated before external adapters are
constructed. The SSH adapter sends an executable and separately Shellwords-escaped arguments; uploads send
base64 over stdin. Hostile tests cover shell metacharacters, command substitution, traversal and embedded
control characters.

### Secrets

Configuration/state store secret-variable names or hashes, never service passwords or provider tokens.
Human, JSON, TUI, file-log, error and support-bundle paths share the central filter. It redacts registered
values, sensitive hash keys, URL credentials and complete private-key blocks. Service `.env` files are mode
`0600`. Redis uses a literal runtime environment reference in its command and `REDISCLI_AUTH` healthcheck so
Compose does not resolve the password into container command arguments.

### SSH and firewall recovery

First-use SSH trust requires the exact displayed SHA256 fingerprint; subsequent access uses the isolated
known-hosts file. User creation validates sudoers with `visudo`. SSH policy validates with `sshd -t`, initially
keeps key-based root recovery, verifies a fresh deploy connection, disables root and verifies again. The
authenticated transition session remains open so a failed fresh verification can restore policy before the
session closes.

UFW adds the desired SSH route before removing stale rules marked by Kitsune Kit. Apply/finalize is verified with a
fresh connection. Rollback preserves pre-existing activation/package state and removes only recorded owned
rules. Docker-published database ports have separately owned `DOCKER-USER` allow/drop transactions.

### Ownership and destruction

Server deletion requires a recorded provider ID, exact-name confirmation and matching provider identity/tags.
Provider deletion happens before DNS cleanup, so a rejected provider deletion leaves DNS unchanged; cleanup is
retryable if DNS fails afterward. DNS updates store every exact ID and prior value immediately.

Service `remove` preserves volumes. `destroy-data` requires `TYPE@ENV`; `--yes` is insufficient. Interactive
use offers a data archive, and automation can request one with `--backup-before-destroy`. Destruction refuses
to proceed when managed state is absent.

### Files, state and supply chain

State, known-hosts, logs and support artifacts use restricted directories/files. State writes lock, validate,
back up, fsync and atomically rename. Unsupported schemas fail instead of being guessed. Logs retain at most 20
files. Temporary installer/key/config files are removed on failures; metrics downloads require an operator-set
SHA256. The internal backup container image is digest-pinned.

Bundler Audit was run with ruby-advisory-db commit
`0c1a72a61f08ac6758c5124c083bf01db4638456` and reported no known vulnerabilities. CI also runs RuboCop,
ShellCheck, branch-coverage gates, adapter contracts, gem build/install smoke tests and the supported Ruby/Ubuntu
matrices.

The local normal suite passed 243 examples with 87.05% line, 66.34% overall branch and 88.99% domain-core
branch coverage. The Docker-backed SSH/Bash/TUI integration passed 8 examples on Ubuntu 22.04 and the same 8
examples on Ubuntu 24.04. Pseudo-terminal cases verify restoration on normal exit and `SIGINT`. These local
results are complemented by the real-provider evidence below.

The baseline suite and core coverage gate passed under the supported Ruby 3.2.2, 3.3 and 3.4 runtimes. Six
additional bounded SSH-bootstrap retry, server-state drift and real SDK-interface examples passed under the
local Ruby 3.2.2 gate.
Standard-library extractions needed by Kitsune Kit and the current DigitalOcean SDK are explicit runtime dependencies,
so warnings cannot corrupt structured output on newer Ruby releases.

## Findings corrected during this review

1. The real E2E CLI checks did not explicitly select the provisioned `e2e` environment. They now do and assert
   that rollback leaves only the server state.
2. Redis authentication was represented in a Compose command form that could resolve the secret into command
   arguments. It now uses a literal runtime environment reference and `REDISCLI_AUTH`.
3. Service data destruction lacked an interactive backup offer and exact-name prompt. Both are now present,
   with an explicit automation flag and tests.
4. Docker repository key/config and sudoers/SSH-policy temporary files could remain partial after interruption.
   They now use guarded temporary files followed by restrictive installation and cleanup traps.
5. The TTL cleanup script had no isolated proof around its destructive filter. It is now dependency-injectable,
   dry-run by default and tested to delete only expired `kitsune-ci` IDs.

## Residual risks and required operational validation

- The real DigitalOcean E2E passed locally on 2026-08-14 in 7 minutes 12 seconds (seed 12020; 1 example, 0
  failures). It exercised provider behavior, Ubuntu 24.04, systemd, UFW, Docker networking, SSH hardening,
  PostgreSQL/Redis isolation, zero-change reapply, rollback and exact Droplet cleanup. The operator confirmed the
  Droplet was removed.
- The same credentialed workflow has not yet been observed on a GitHub-hosted runner, so runner permissions,
  secret wiring and cleanup-job orchestration remain release gates.
- Ruby 4 is outside the 0.5.0 support contract because the current DigitalOcean SDK constrains
  `faraday-retry` to a release series that requires Ruby `< 4`; CI and gem metadata enforce this boundary.
- User-selected PostgreSQL/Redis image tags are mutable unless pinned by digest. Production configurations
  should pin and deliberately update reviewed multi-platform digests.
- Data archives are created on the same Droplet. They are not disaster recovery until copied to independent,
  access-controlled storage and restoration is tested.
- Local state is not encrypted or centrally shared. It contains no intended secrets, but its integrity and
  availability establish ownership; secure backups are required for team operation.
- Provider token least privilege and budget controls depend on DigitalOcean account capabilities and operator
  configuration. Use a separate CI project/account, alerts and short-lived or narrowly scoped credentials where
  available.
- Docker-group and passwordless-sudo membership make the deploy key root-equivalent by design.

## Release decision

The reviewed implementation passed its real-provider lifecycle, including confirmed cleanup and closed ports
5432/6379. The review supports the 0.5.0 release; hosted CI and timed new-user acceptance remain follow-up
evidence before 1.0 rather than unresolved security findings.
