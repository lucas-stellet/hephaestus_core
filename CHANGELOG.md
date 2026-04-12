# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Support `:id`, `:workflow_version`, and `:status_in` filters in the ETS storage adapter's `query/1` implementation.

## [0.2.1] - 2026-04-09

### Fixed

- Include `config_key: __MODULE__` in macro-generated `runner_opts/0` so that external runners (e.g. `HephaestusOban.Runner`) receive the key needed to resolve runtime config from `:persistent_term`.

## [0.2.0] - 2026-04-08

### Added

- Workflow versioning: all workflows now have an implicit version (default `1`).
- `version:` option for `use Hephaestus.Workflow` to declare explicit version numbers.
- `versions:` and `current:` options for umbrella workflow modules (version dispatchers).
- Generated functions on umbrella modules: `__versions__/0`, `current_version/0`, `resolve_version/1`, overridable `version_for/2`, and `__version__/0` returning `nil`.
- Umbrella modules do not generate DAG helper functions such as `__graph__/0`, `__edges__/0`, or `__predecessors__/1`.
- Generated functions on all workflows: `__version__/0`, `__versioned__?/0`, `resolve_version/1`.
- `workflow_version` field on `Hephaestus.Core.Instance` (positive integer, default `1`).
- `Instance.new/3` accepting `(workflow, version, context)` with guard rejecting non-positive versions.
- `workflow_version` included in all telemetry event metadata for observability of which version is running.
- Version resolution chain in `start_instance/3`: `opts[:version]` (explicit) -> `version_for/2` callback (umbrella only) -> `current_version/0` (compile default). Non-versioned workflows skip the chain and call `resolve_version/1` directly.
- Compile-time validations for umbrella workflow modules: `version:` cannot be combined with `versions:`, version keys must be positive integers, `current` must be present in `versions`, version modules must implement `Hephaestus.Core.Workflow`, `__version__/0` must match the version key, and version modules must be nested under the umbrella namespace.
- Workflow Versioning guide (`guides/versioning.md`).

### Changed

- `Instance.new/3` added with a version parameter. Existing `new/2` signatures are preserved for backward compatibility.

## [0.1.5] - 2026-04-08

### Added

- Telemetry event emission for workflow and step lifecycle (11 events).
- `Hephaestus.Telemetry` module with emission helpers for all events.
- `Hephaestus.Telemetry.LogHandler` for structured Logger output with configurable log levels and event filtering.
- `Hephaestus.Telemetry.Metrics` with 9 pre-built metric definitions for Prometheus, StatsD, and LiveDashboard.
- `telemetry_metadata` option on `start_instance/3` for caller-supplied correlation data (request IDs, user IDs, trace context).
- `telemetry_start_time` on Instance for workflow duration tracking.
- Telemetry instrumentation in `Runner.Local` for all lifecycle points: workflow start/stop/exception, step start/stop/async/exception/resume, engine advance, and workflow transitions.
- `advance_count`, `step_count`, and `waiting_since` tracking in `Runner.Local` GenServer state.
- Telemetry event reference guide (`guides/telemetry.md`).
- New dependencies: `:telemetry ~> 1.0`, `:telemetry_metrics ~> 1.0`.

### Changed

- `start_instance/2` now accepts optional third argument (opts keyword list).
- `Instance` struct has two new fields with defaults (non-breaking).

## [0.1.4] - 2026-04-08

### Added

- Runtime metadata support: steps can return `{:ok, event, context_updates, metadata_updates}` to emit dynamic metadata during execution.
- `runtime_metadata` field on `Hephaestus.Core.Instance` for accumulating step-emitted metadata.

## [0.1.3] - 2026-04-07

### Added

- `tags` and `metadata` options to `use Hephaestus.Workflow` for annotating workflows with custom classification and runtime data.

### Changed

- Updated guides to document workflow tags and metadata usage.

## [0.1.2] - 2026-04-07

### Added

- Getting Started guide with step-by-step onboarding.
- Architecture guide explaining the engine internals.
- Extensions guide for custom storage and runner adapters.
- Usage examples in `@doc` annotations and documentation for `Workflow` generated functions.
- ExDoc configured with guide groups and module groups.

## [0.1.1] - 2026-04-06

### Added

- Optional `retry_config/0` callback to the `Step` behaviour.
- `@doc` and `@typedoc` annotations to all public modules, functions, and types.
- hex.pm package metadata for publishing.

### Changed

- `schedule_resume` return type changed to `{:ok, term()}` for adapter flexibility.

## [0.1.0] - 2026-04-06

### Added

- Hephaestus Core MVP — lightweight workflow engine for Elixir/OTP.
- Callback-based workflow definition with `use Hephaestus.Workflow`.
- `Engine` for workflow activation and execution with DAG-based step traversal.
- `Instance` and `Context` structs for workflow state management.
- Built-in steps: `Done`, `Wait`, `WaitForEvent`, `Debug`.
- `Step` behaviour with pattern-matching callbacks (`handle_execute/3`, `handle_transit/3`).
- `Runner` behaviour and `Runner.Local` default implementation.
- `Storage` behaviour and `Storage.ETS` default implementation.
- Support for `{module, opts}` tuples in `use Hephaestus` storage/runner config.
- `Connector` behaviour for external integrations.
- `mix hephaestus.gen.docs` task for ASCII execution graph generation.
- `libgraph` dependency for workflow graph operations.
- Comprehensive README in English and Portuguese.

[0.2.0]: https://github.com/hephaestus-org/hephaestus_core/compare/v0.1.5...v0.2.0
[0.1.5]: https://github.com/hephaestus-org/hephaestus_core/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/hephaestus-org/hephaestus_core/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/hephaestus-org/hephaestus_core/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/hephaestus-org/hephaestus_core/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/hephaestus-org/hephaestus_core/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/hephaestus-org/hephaestus_core/releases/tag/v0.1.0
