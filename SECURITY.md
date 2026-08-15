# Security policy

## Supported versions

Kitsune Kit is pre-1.0 software. Security fixes are provided for the latest release. Minor releases may change commands, configuration and state schemas until 1.0, so infrastructure state must be backed up before upgrading.

## Reporting a vulnerability

Do not open a public issue for vulnerabilities that could expose credentials, execute injected commands, destroy infrastructure or lock users out of servers. Report them privately to `contact@omarherrera.me` with:

- affected version or commit;
- reproduction steps;
- impact;
- suggested remediation, if known.

Do not include real tokens, keys, domains or server addresses. An acknowledgement should be expected within seven days.

## Security guarantees under development

- Databases are private by default.
- Secrets are never written to state or normal logs.
- SSH host keys are verified.
- Destructive operations require explicit confirmation.
- Rollback only changes resources recorded as managed by Kitsune Kit.
- User input is validated before reaching shell commands.
