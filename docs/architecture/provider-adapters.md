# Provider and transport adapters

Kitsune Kit's adapter API version is `Kitsune::Kit::Adapters::API_VERSION`, currently `1`. It is a small internal extension boundary, not a dynamic plugin system. A breaking signature or semantic change must increment this value and the corresponding JSON/event schemas when affected.

## Provider contract

A provider subclasses `Kitsune::Kit::Adapters::Provider` and implements:

| Method | Contract |
| --- | --- |
| `validate_credentials!` | Return `true`, or raise a typed authentication/provider error. |
| `validate_server_spec!(spec:)` | Check region, size and image availability without creating anything. |
| `find_server(name:, tags:)` | Return an exact owned `ServerRecord` or `nil`; never adopt by name alone. |
| `find_server_by_id(id:)` | Return the exact record or `nil`. |
| `create_server(spec:)` | Create once and return the provider ID immediately. |
| `wait_until_ready(id:, timeout:)` | Return an active record with a public IP or raise `TimeoutError`. |
| `delete_server(id:)` | Delete by exact provider ID. |
| DNS methods | Find/upsert/delete records while preserving exact IDs and zones. |

Provider exceptions must be translated into `Kitsune::Kit::Errors` without copying tokens or raw provider response bodies into messages. Availability errors are configuration errors because the user can correct the desired spec; transient API failures remain retryable provider errors.
The CLI `--timeout` value configures both DropletKit open/read timeouts and the separate readiness deadline.

## Transport contract

A transport subclasses `Kitsune::Kit::Adapters::Transport`. `execute` receives a command and a separate argument array, applies a deadline, and returns `CommandResult` with independent `stdout`, `stderr`, `exit_status` and `duration_ms`. It does not infer success from output. `upload` accepts explicit content, absolute normalized path and restrictive mode. Host-key verification belongs to the connection adapter and must never silently disable verification.

## Verification

The same shared examples run against `FakeProvider`/`DigitalOceanProvider` and `FakeTransport`/`NetSshTransport`. They cover credentials, spec validation, lifecycle, DNS, reachability, result shape, uploads and timeout mapping. Adapter-specific tests cover provider error translation, SSH quoting, unsafe paths, host keys and failed uploads.

Run them with:

```bash
bundle exec rspec spec/adapters spec/contracts
```

Do not add a provider until it can pass these contracts and an opt-in real lifecycle test. The Hetzner
feasibility/sequencing review and the decision not to create a premature hook system are recorded in
[Roadmap and extension decisions](../roadmap.md).

The state boundary follows the same rule: `StateStores::Store` defines the port, while `StateStore` is the locked atomic filesystem adapter and `Adapters::FakeStateStore` is the deterministic in-memory adapter. Both execute `spec/contracts/state_store_contract.rb`.

`SecretStores::Store` and `Reporters::Reporter` are also explicit ports. Environment/fake secret stores and
human/JSON/fake reporters execute their shared contracts in `spec/adapters`; fakes make complete workflow tests
independent of the process environment and terminal.

`Clock` is the time port for workflow event timestamps, monotonic durations, journals and bounded waits.
`Adapters::FakeClock` advances deterministically without sleeping; both implementations execute
`spec/contracts/clock_contract.rb`.
