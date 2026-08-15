# DigitalOcean provider

DigitalOcean is the only provider supported in the 0.5 release. Provider calls are isolated behind the provider contract so the core and presentation layers do not depend on DropletKit directly.

## Credentials and permissions

Set `provider.token_env` to the name of a process environment variable (default `DO_API_TOKEN`) and export the token before running Kitsune Kit.

The token needs Droplet read/write access. DNS read/write access is required only when `dns.domains` is non-empty. Prefer a dedicated account/project for CI and test resources, and grant the minimum scopes available for your workflow.

## SSH key IDs

`server.ssh_key_id` is the DigitalOcean key ID, not a filesystem path or public-key text. `ssh.key_path` is the corresponding local private key. Kitsune Kit passes the ID only during Droplet creation and never displays it in plan details.

For the exact commands to create a dedicated test key, upload its public half, retrieve the numeric ID and
configure local or GitHub E2E runs, see [DigitalOcean E2E](../testing.md#digitalocean-e2e).

## Identity and ownership

A server match requires both the exact configured name and all configured tags. Keep the default `kitsune-managed` tag. State stores the returned provider ID immediately after creation.

Deletion requires:

1. an ID present in local managed state;
2. the provider object still existing or being confirmed absent;
3. exact configured name and expected tags when it exists;
4. exact operator confirmation.

Kitsune Kit never deletes a Droplet by name alone and never adopts a same-name untagged Droplet.

## Creation and timeouts

Before server lookup or creation, Kitsune Kit queries DigitalOcean's region, size and distribution-image catalogs. The selected region must be active, the size must be available there, and the image must support it. An unavailable choice is an actionable configuration error; no Droplet is created.

The creation request includes name, region, size, supported Ubuntu image, SSH key ID and tags. Kitsune Kit polls until the Droplet is active and has a public IPv4 address. A timeout is retryable: the saved provider ID lets `kit resume` wait for the same Droplet instead of creating another.

Provider authentication, quota, validation and connectivity errors are mapped to stable domain error codes. Technical provider messages are not treated as safe user output.

## DNS

For each hostname, Public Suffix List rules determine the zone and relative record name. Kitsune Kit finds records by exact zone/name/type, persists returned record IDs and captures previous values before an update.

Rollback deletes records it created and restores records it updated. If a run fails between records, each completed record is already in state and resume does not duplicate it.

The zone must already exist in the DigitalOcean account; Kitsune Kit does not transfer domains or change nameservers.

## Real-infrastructure tests

The manually dispatched E2E suite uses unique names, tags every Droplet with `kitsune-ci` and
`kitsune-expires-EPOCH`, saves state immediately and destroys in `ensure`. A separate always-run cleanup job
deletes only expired resources carrying both conventions after an authorized workflow run. See
[Testing](../testing.md).
