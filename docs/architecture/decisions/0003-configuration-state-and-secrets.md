# ADR 0003: Configuration, state and secrets

- Status: accepted
- Date: 2026-08-14

## Decision

- `.kitsune/config.yml` contains versioned, non-secret project configuration.
- `.kitsune/environments/<name>.yml` contains versioned environment overrides.
- `.kitsune/state/<name>.json` contains versioned, non-secret managed-resource state.
- Secrets come from environment variables initially. Secret-store adapters may be added later.
- Configuration precedence is CLI, environment variables, the selected environment file, project file, safe defaults.
- The active environment is selected by `--env`, then `KITSUNE_ENV`, then `.kitsune/environment`, then `development`.
- State writes are locked and atomic.
- State stores provider IDs and previous managed values; deletion never relies only on a resource name.
- Reporters pass all values through one secret filter.
- Version 1 is the new product baseline; legacy preview formats are not migrated or interpreted.
- Any future schema transition must be an explicit, tested adjacent-version migration that preserves a backup.
- Unknown/future configuration and state versions fail with compatible-version or migration guidance.

## Consequences

Existing `.env` infrastructure files are not read by the new product. Sensitive data is never persisted in state or diagnostic bundles.
