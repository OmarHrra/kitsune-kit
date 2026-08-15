# Getting started

This guide creates a new DigitalOcean server from an empty project. Read the plan before applying it; a real run creates billable infrastructure.

## 1. Prepare DigitalOcean

Create a DigitalOcean API token with the minimum access needed to inspect/create/delete Droplets and, only if configured, domain records. Keep development/CI infrastructure in a separate project or account where practical.

Upload your public SSH key to DigitalOcean and note its numeric key ID. Kitsune Kit needs the provider key ID at creation time and the corresponding private key locally.

```bash
chmod 600 ~/.ssh/id_ed25519
export DO_API_TOKEN="your-token"
```

Do not put the token or a private key in `.kitsune/config.yml`.

## 2. Initialize the project

```bash
mkdir myapp-infrastructure
cd myapp-infrastructure
kit init
```

Generated files:

```text
.kitsune/config.yml
.kitsune/environments/development.yml
.kitsune/environment
```

Kitsune Kit adds state, logs, support bundles, known hosts and the selected environment to `.gitignore`. Commit the non-secret configuration files; back up `.kitsune/state/` securely outside Git once resources exist.

`kit init` does not overwrite generated files. `kit init --force` replaces them and should only be used intentionally.

## 3. Edit configuration

At minimum, replace:

```yaml
server:
  name: myapp-development
  region: sfo3
  size: s-1vcpu-1gb
  image: ubuntu-24-04-x64
  ssh_key_id: "12345678"

ssh:
  key_path: ~/.ssh/id_ed25519
```

Keep `services.postgres.publish` and `services.redis.publish` false unless remote TCP access is a deliberate requirement. See [Configuration](configuration.md).

## 4. Run preflight checks

```bash
kit doctor
```

Before the Droplet exists, `doctor` reports it as a warning. Configuration, local key permissions, provider credentials and state should pass. `doctor` never creates or modifies resources.

## 5. Review the plan

```bash
kit plan
```

Markers are:

```text
+ create
~ update
- delete
= no change
```

A planned immutable server change is destructive and `apply` refuses to replace it implicitly. Destroying a server is always a separate, explicitly confirmed action.

## 6. Apply

```bash
kit apply
```

Kitsune Kit creates and records the provider ID before waiting, so a timeout can be resumed without creating a duplicate. Remote operations then configure the user, SSH, firewall, updates, swap, Docker, optional services and DNS.

On the first SSH connection, Kitsune Kit displays the key type and SHA256 host-key fingerprint. Verify it through an independent trusted channel before accepting it. The accepted key is stored in `.kitsune/known_hosts` with restricted permissions.

If a step fails:

```bash
kit status
kit resume
```

Only unfinished steps from a compatible saved run are executed. Do not delete state to work around a failure.

## 7. Verify and reapply

```bash
kit doctor
kit plan
kit apply
```

After a successful run, `doctor` should pass and `plan` should contain zero changes. Repeated `apply` is expected to be idempotent.

## Non-interactive first run

CI cannot answer confirmation or host-key prompts. First obtain and independently verify the expected fingerprint. Then run:

```bash
kit plan --format json --no-input
kit apply \
  --format json \
  --no-input \
  --yes \
  --trust-host-key SHA256:verified-fingerprint
```

The fingerprint option must match exactly. It is not a switch that disables host-key verification.

## Production checklist

- Use a dedicated environment overlay and `kit env use production`.
- Restrict `ssh.allowed_cidrs` to operator/CI networks when practical.
- Keep data services private or specify the smallest possible allowed CIDRs.
- Use generated, unique PostgreSQL and Redis passwords.
- Run `doctor`, archive the reviewed JSON plan and back up local state.
- Test service backup and restore procedures before relying on them.
- Retain provider-console access while changing SSH policy.
