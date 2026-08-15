# Kitsune Kit

Kitsune Kit prepares Ubuntu servers for Docker and Kamal deployments through a predictable, inspectable CLI.

> Status: `0.5.0` (pre-1.0). DigitalOcean and Ubuntu 22.04/24.04 LTS are supported. The command, configuration and state schemas may still change before 1.0.

## What it does

- Provisions an explicitly tagged DigitalOcean Droplet.
- Configures a deploy user, verified SSH policy, UFW, swap and unattended security updates.
- Installs Docker Engine and Docker Compose from Docker's official Ubuntu repository.
- Optionally installs private PostgreSQL/Redis services or represents provider-managed external endpoints.
- Creates exact DNS records without adopting unrelated resources.
- Shows a plan before changing infrastructure and records managed state for resume and rollback.
- Offers both a conventional CLI and an optional full-screen TUI over the same workflows.

Kitsune Kit is not a general-purpose configuration manager and does not manage arbitrary existing servers. It only removes resources recorded in its local state.

## Requirements

- Ruby 3.2 or newer.
- A DigitalOcean account, API token and uploaded SSH public key.
- A local private SSH key with restricted permissions.
- A project directory whose `.kitsune/` state can be backed up securely.

## Installation

```bash
gem install kitsune-kit
```

Or add it to a project:

```ruby
gem "kitsune-kit", "~> 0.5.0"
```

## Safe quick start

```bash
kit init

# Edit .kitsune/config.yml first.
export DO_API_TOKEN="..."

kit doctor
kit plan
kit apply
```

`kit apply` asks for confirmation. In automation, review the plan and use `kit apply --no-input --yes`. The first SSH connection also requires verifying the displayed host-key fingerprint; non-interactive runs must pass the exact value with `--trust-host-key`.

The recommended workflow is always:

```text
init -> edit configuration -> doctor -> plan -> apply -> doctor
```

See [Getting started](docs/getting-started.md) for the complete first-run procedure.

## Commands

| Command | Purpose | Changes resources |
| --- | --- | --- |
| `kit init` | Create project configuration | Local |
| `kit doctor` | Check configuration, credentials, connectivity and drift | No |
| `kit plan` | Show the desired changes | No |
| `kit apply` | Apply the reviewed plan | Yes |
| `kit resume [RUN_ID]` | Continue an incomplete run | Yes |
| `kit status` | Show tracked state and the server | No |
| `kit server import` | Recover a verified server ID after state loss | Exact name |
| `kit rollback` | Restore managed configuration; preserve server and service data | Yes |
| `kit server ACTION` | Show, create, configure, connect to or destroy the server | Depends |
| `kit service TYPE ACTION` | Manage PostgreSQL or Redis | Depends |
| `kit dns ACTION` | List, plan, apply or remove configured records | Depends |
| `kit docker ACTION` | Inspect, install or uninstall Docker | Depends |
| `kit env ACTION [NAME]` | List, read or select environments | Local |
| `kit support bundle` | Create a local redacted diagnostic file | Local |
| `kit ui` | Open the optional interactive terminal interface | Depends |

Run `kit help` or `kit help COMMAND` for built-in help. The complete action and option reference is in [Commands](docs/commands.md).

## Configuration and environments

The base configuration is `.kitsune/config.yml`. Environment overlays live at `.kitsune/environments/NAME.yml`. Selection precedence is:

1. `--env NAME`
2. `KITSUNE_ENV`
3. `.kitsune/environment`
4. `development`

Within a selected environment, value precedence is defaults, base file, environment overlay, supported environment-variable overrides, then explicit internal API overrides. Tokens and service passwords are read from environment variables and are never stored in configuration or state.

See [Configuration](docs/configuration.md).

## Security model

- PostgreSQL and Redis have no published host port by default.
- Publishing a data port requires explicit allowed CIDRs; Kitsune Kit also manages matching `DOCKER-USER` firewall rules.
- SSH host keys use trust-on-explicit-confirmation and are subsequently checked strictly.
- Shell arguments are validated and passed separately; uploaded scripts and configuration use restricted modes.
- State writes are locked and atomic, with a recoverable backup.
- Logs and support bundles are redacted and never uploaded automatically.
- Destructive commands require exact or explicit confirmation.

Read [Security](docs/security.md) before managing production infrastructure.

## PostgreSQL and Redis

Services are optional and disabled initially. Enable a service in configuration and export its configured secret:

```bash
export POSTGRES_PASSWORD="$(ruby -rsecurerandom -e 'print SecureRandom.base64(36)')"
kit service postgres install
```

`remove` stops/removes containers but preserves the Docker volume. `destroy-data` permanently removes it and requires `--confirm-destroy TYPE@ENV`. Create a backup first.

See [PostgreSQL](docs/services/postgres.md) and [Redis](docs/services/redis.md).

## CLI and optional TUI

Kitsune Kit is fully usable without the TUI. Every infrastructure action available in the full-screen interface invokes the same domain workflow and has a conventional command equivalent. Scripts and CI should use subcommands, `--no-input`, and optionally `--format json`.

With no arguments, `kit` opens the TUI only when both standard input and output are terminals; otherwise it prints help. Use `kit ui` to request it explicitly. See [TUI](docs/tui.md).

## Automation and JSON

```bash
kit plan --format json --no-input --no-color
kit apply --format json --no-input --yes
```

JSON documents include `schema_version`, command/run metadata, status, result, warnings and domain events. Errors are emitted as a versioned JSON object on standard error and have documented exit codes. Do not parse human output.

## Development

```bash
bin/setup
bundle exec rake test
bundle exec rake lint
bundle exec rake security
bundle exec rake integration
bundle exec rake ci
```

Docker-backed integration tests and credential-gated DigitalOcean E2E tests are intentionally separate. See [Testing](docs/testing.md) and [Contributing](CONTRIBUTING.md).

## Documentation

- [Getting started](docs/getting-started.md)
- [Configuration](docs/configuration.md)
- [Command reference](docs/commands.md)
- [Security](docs/security.md)
- [Manual security audit](docs/security-audit.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Architecture](docs/architecture.md)
- [Testing](docs/testing.md)
- [Releasing](docs/releasing.md)
- [Roadmap and extension decisions](docs/roadmap.md)

## Roadmap and stability

The current focus is stabilizing the DigitalOcean lifecycle, schema migrations and real-infrastructure E2E coverage before 1.0. Additional providers and extension hooks will be considered only after those contracts are stable.

Security reports follow [SECURITY.md](SECURITY.md). Changes are recorded in [CHANGELOG.md](CHANGELOG.md).

## License

Kitsune Kit is available under the [MIT License](LICENSE.txt).
