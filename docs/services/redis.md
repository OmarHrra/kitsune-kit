# Redis service

Redis is an optional Docker Compose service managed by Kitsune Kit on the target server. It is disabled, password-protected and private by default.

## Enable

```yaml
services:
  redis:
    enabled: true
    image: redis:7.2
    publish: false
    bind: 127.0.0.1
    allowed_cidrs: []
    port: 6379
    password_env: REDIS_PASSWORD
```

```bash
export REDIS_PASSWORD="$(ruby -rsecurerandom -e 'print SecureRandom.base64(36)')"
kit plan
kit service redis install
```

The generated service enables append-only persistence, requires the password and attaches to `kitsune-private`. Data lives in the Compose named `data` volume.

## Connectivity and publishing

With `publish: false`, only containers on the private Docker network can connect. If TCP access from outside the host is unavoidable, set `publish: true`, choose a bind address and provide narrow `allowed_cidrs`. Kitsune Kit installs matching `DOCKER-USER` rules and a final drop rule it owns.

Never treat the Redis password as an adequate substitute for network isolation. Validate port 6379 from an untrusted external network after any firewall/Docker change.

## Lifecycle

```bash
kit service redis status
kit service redis backup
kit service redis remove --yes
kit service redis destroy-data --backup-before-destroy --confirm-destroy redis@production
```

- `backup` pauses Redis, archives its volume remotely, then unpauses even if archiving fails.
- `remove` removes the container and owned firewall rules but preserves the data volume.
- `destroy-data` removes the volume, service files, backups and state after exact confirmation.
- `kit rollback` restores captured managed files/settings while preserving data.

Copy backups away from the Droplet, control access to them and regularly test restoration. Image downgrades may not understand data written by a newer Redis version; operational rollback and data-format compatibility are separate concerns.

## External Redis

Set `enabled: true`, `mode: external`, `host` and `port` for a provider-managed endpoint. Status is available,
but Kitsune Kit refuses install, backup, remove and destroy-data because those belong to the external provider. TLS,
availability and backup policy remain the operator/provider responsibility.
