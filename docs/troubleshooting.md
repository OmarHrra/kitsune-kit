# Troubleshooting

Start with read-only evidence:

```bash
kit doctor --debug
kit status
kit plan
```

Do not delete `.kitsune/state/` or provider resources just to retry. The state is what prevents duplicate creation and unsafe deletion.

If the primary state file and `.backup` are both unavailable, recover only an independently verified server identity with:

```bash
kit server import \
  --provider-id EXACT_NUMERIC_DROPLET_ID \
  --confirm-import CONFIGURED_SERVER_NAME
kit doctor
```

Import checks the complete configured identity and records no SSH, firewall, Docker, service or DNS ownership. `doctor` and `plan` must be reviewed afterward; do not assume pre-existing remote files belong to Kitsune Kit.

## Configuration file not found

Run from the project root or pass `--root PATH`. Initialize once with `kit init`. If using `--config`, it must point to the base YAML file; relative environment overlays still come from the selected project root.

## Invalid configuration

Kitsune Kit reports every validation finding together when possible. Common causes:

- placeholder `server.ssh_key_id` was not replaced;
- service enabled without its password environment variable;
- unsupported Ubuntu image slug;
- published service has no allowed CIDR;
- YAML boolean was quoted or malformed;
- metrics enabled without a verified lowercase SHA256;
- environment or resource name contains spaces/metacharacters.

Correct the source file/environment variable and rerun `doctor` and `plan`.

## Provider authentication or API error

Confirm the environment variable named by `provider.token_env` is exported in the same process. Check token expiration/scopes, account/project, quota and region/size availability. Use `--debug` for the safe error class/context; Kitsune Kit intentionally does not print raw provider responses that might include sensitive details.

## Server creation timed out

Run `kit status` before doing anything else. If state contains the provider ID, do not create another Droplet manually. Inspect that exact ID in DigitalOcean, resolve provider/network delays, then:

```bash
kit resume
```

## SSH host key is not trusted

This is expected on first contact. Verify the displayed SHA256 fingerprint independently. Interactive mode can save it. For automation:

```bash
kit doctor --no-input --trust-host-key SHA256:verified-value
```

A changed key can indicate server replacement or interception. Compare provider ID/state and investigate; do not remove known-host state reflexively.

## Neither deploy nor root can connect

Use DigitalOcean's console/recovery access and verify:

- the configured private key matches the uploaded key ID;
- deploy user's `authorized_keys` and permissions;
- configured SSH port and UFW rules;
- `sshd -t` and service status;
- your source IP remains in `ssh.allowed_cidrs`.

Kitsune Kit validates the deploy connection before disabling bootstrap assumptions, but out-of-band changes can still remove access.

## Remote command or verification failed

The error identifies the resource and stable code. Inspect the redacted session log under `.kitsune/logs/`, repair the underlying condition and use `kit resume`. A failed operation is not marked successful; temporary uploads are cleaned best-effort.

For Docker failures, inspect disk space, conflicting packages, apt repository reachability, daemon status and `docker compose version`. For services, inspect Compose health/logs and the configured image architecture.

Kitsune Kit refuses to remove Ubuntu/community Docker packages (`docker.io`, legacy Compose, `podman-docker`, `containerd` or `runc`) automatically because doing so could disrupt an existing installation. Migrate/remove those packages deliberately, preserve any existing Docker data, then rerun the plan.

## Plan always reports drift

`doctor` compares remote fingerprints and local ownership. Common causes are manual edits to managed files, missing markers, environment mismatch or restored server data with stale local state. Preserve `.kitsune/state/ENV.json` and its `.backup`; compare exact provider IDs and fingerprints. Do not adopt/delete by name without a deliberate recovery procedure.

## PostgreSQL or Redis is publicly reachable

Treat this as urgent. Stop/remove the service or close the provider/network firewall, then inspect:

```bash
kit doctor
kit service TYPE status
```

Ensure `publish: false`, or narrow `bind`/`allowed_cidrs`. Inspect Docker's `DOCKER-USER` chain as well as UFW because published Docker ports can bypass ordinary UFW forwarding rules.

## Apply/resume asks for confirmation in CI

Use both flags after reviewing the plan:

```bash
kit apply --no-input --yes --format json
kit resume --no-input --yes --format json
```

Permanent destruction still needs `--confirm-destroy`; this cannot be bypassed by `--yes`.

## TUI does not open

The TUI requires interactive stdin and stdout. Redirected/piped sessions should use conventional commands. Explicit `kit ui` without a TTY returns a configuration error instead of emitting terminal escape sequences. Minimum display size is 70×18.

## Create a support bundle

```bash
kit support bundle
```

Kitsune Kit writes the restricted JSON file and prints its redacted contents in human mode. Review that output before
sharing it; the bundle is never uploaded automatically. With `--format json`, inspect the returned local path.

Open the generated JSON and inspect it before sharing. It is permission-restricted and redacted, but Kitsune Kit never uploads it or asserts that arbitrary user content cannot contain sensitive business data.
