# Task Plan: Unique Business Key & Workflow Facade

> Generated from: `docs/superpowers/specs/2026-04-10-unique-business-key-facade-design.md`
> Total tasks: 11 (core) + 4 (extensions) | Waves: 5 (core) + 2 (extensions) | Max parallelism: 3

**TDD Discipline:** Every task follows RED-GREEN-REFACTOR. The agent writes tests FIRST (RED), implements to make them pass (GREEN), then refactors. Test files are listed before implementation files in each task.

**Note:** Tasks for hephaestus_ecto and hephaestus_oban are separated and execute after core is complete.

## hephaestus_core Waves

### Wave 0 — Foundation structs and modules (3 agents)
| Task | Title | Effort | Files |
|------|-------|--------|-------|
| [task-001](task-001.md) | Create `Hephaestus.Workflow.Unique` struct with validations | S | `lib/hephaestus/core/workflow/unique.ex`, `test/hephaestus/core/workflow/unique_test.exs` |
| [task-002](task-002.md) | Create `Hephaestus.Uniqueness` module (ID build, validate, extract) | M | `lib/hephaestus/uniqueness.ex`, `test/hephaestus/uniqueness_test.exs` |
| [task-003](task-003.md) | Create `Hephaestus.Instances` registry + Tracker | M | `lib/hephaestus/instances.ex`, `lib/hephaestus/instances/tracker.ex`, `test/hephaestus/instances_test.exs` |

### Wave 1 — Core adaptations (3 agents)
| Task | Title | Effort | Files | Depends on |
|------|-------|--------|-------|------------|
| [task-004](task-004.md) | Refactor `Instance.new` to require explicit ID | M | `lib/hephaestus/core/instance.ex`, `test/hephaestus/core/instance_test.exs`, `test/hephaestus/core/instance_v2_test.exs` | task-001 |
| [task-005](task-005.md) | Extend `Storage.ETS` with new query filters | M | `lib/hephaestus/runtime/storage/ets.ex`, `test/hephaestus/runtime/storage/ets_test.exs` | task-001 |
| [task-006](task-006.md) | Add `Uniqueness.check/5` (scope-based uniqueness check) | M | `lib/hephaestus/uniqueness.ex`, `test/hephaestus/uniqueness_test.exs` | task-002, task-005 |

### Wave 2 — Workflow macro + entry-point (3 agents)
| Task | Title | Effort | Files | Depends on |
|------|-------|--------|-------|------------|
| [task-007](task-007.md) | Add `unique` option to Workflow DSL + generate `__unique__/0` | M | `lib/hephaestus/core/workflow.ex`, `test/hephaestus/core/workflow_unique_test.exs` | task-001 |
| [task-008](task-008.md) | Update `Hephaestus.__using__` (Tracker, custom ID in start_instance) | M | `lib/hephaestus.ex`, `lib/hephaestus/application.ex`, `test/hephaestus/entry_module_test.exs` | task-003, task-004 |
| [task-009](task-009.md) | Update `Runner.Local` to accept custom ID | M | `lib/hephaestus/runtime/runner/local.ex`, `test/hephaestus/runtime/runner/local_test.exs`, `test/hephaestus/runtime/runner/local_v2_test.exs` | task-004, task-008 |

### Wave 3 — Facade generation (1 agent)
| Task | Title | Effort | Files | Depends on |
|------|-------|--------|-------|------------|
| [task-010](task-010.md) | Generate facade functions in Workflow macro | L | `lib/hephaestus/core/workflow.ex`, `test/hephaestus/core/workflow_facade_test.exs` | task-006, task-007, task-008 |

### Wave 4 — Test fixtures + integration (1 agent)
| Task | Title | Effort | Files | Depends on |
|------|-------|--------|-------|------------|
| [task-011](task-011.md) | Update all test support files and run full integration tests | L | `test/support/*.ex`, `test/hephaestus/versioned_workflow_integration_test.exs`, `CHANGELOG.md` | task-009, task-010 |

---

## hephaestus_ecto Waves (execute after core 0.2.0 published)

### Wave E0 — Ecto adaptations (2 agents)
| Task | Title | Effort | Files | Depends on |
|------|-------|--------|-------|------------|
| [task-E01](task-E01.md) | Extend Ecto storage query with new filters | M | hephaestus_ecto repo | core complete |
| [task-E02](task-E02.md) | Update Ecto runner to accept custom ID | M | hephaestus_ecto repo | core complete |

## hephaestus_oban Waves (execute after ecto 0.2.0 published)

### Wave O0 — Oban adaptations (2 agents)
| Task | Title | Effort | Files | Depends on |
|------|-------|--------|-------|------------|
| [task-O01](task-O01.md) | Update Oban runner to accept custom ID + advisory lock | L | hephaestus_oban repo | ecto complete |
| [task-O02](task-O02.md) | Update Oban storage query filters | M | hephaestus_oban repo | ecto complete |

---

## Dependency Graph

```
task-001 ──→ task-004 ──→ task-008 ──→ task-009 ──→ task-011
task-001 ──→ task-005 ──→ task-006 ──→ task-010 ──→ task-011
task-001 ──→ task-007 ──→ task-010
task-002 ──→ task-006
task-003 ──→ task-008

task-011 ──→ task-E01 ──→ task-O01
task-011 ──→ task-E02 ──→ task-O02
```

## File Conflict Check

| File | Tasks | Waves | Conflict? |
|------|-------|-------|-----------|
| `lib/hephaestus/core/workflow.ex` | task-007, task-010 | W2, W3 | No — different waves |
| `lib/hephaestus/uniqueness.ex` | task-002, task-006 | W0, W1 | No — different waves |
| `test/hephaestus/uniqueness_test.exs` | task-002, task-006 | W0, W1 | No — different waves |
| `test/support/*.ex` | task-011 only | W4 | No — consolidated in single task |
| `lib/hephaestus.ex` | task-008 only | W2 | No — single task |
| `lib/hephaestus/application.ex` | task-008 only | W2 | No — single task |

No file conflicts within any wave.

## Notes

- Max parallelism capped at 3 agents per wave
- Extension tasks (E01/E02, O01/O02) are in separate repos — execute after core is published
- All test workflows need `unique:` added — consolidated in task-011 to avoid file conflicts
- `CHANGELOG.md` is only touched in task-011 (final wave)
