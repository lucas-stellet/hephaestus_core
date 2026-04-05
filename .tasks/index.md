# Task Plan: Hephaestus Core MVP

> Generated from: .compozy/tasks/hephaestus-core/_prd.md + _techspec.md
> Total tasks: 13 | Waves: 7 | Max parallelism: 3

## Waves

### Wave 0 — Foundation (structs, protocols, behaviours independentes)
| Task | Title | Effort | Files |
|------|-------|--------|-------|
| [task-001](task-001.md) | Core data structs + StepDefinition protocol | M | `lib/hephaestus/core/{context,instance,workflow,step,execution_entry,step_definition}.ex` |
| [task-008](task-008.md) | Connector behaviour | S | `lib/hephaestus/connectors/connector.ex` |

### Wave 1 — Behaviours e validação (desbloqueiam o engine)
| Task | Title | Effort | Files | Depends on |
|------|-------|--------|-------|------------|
| [task-002](task-002.md) | Step behaviour + Built-in steps | M | `lib/hephaestus/steps/{step,end_step,debug,wait,wait_for_event}.ex` | task-001 |
| [task-003](task-003.md) | Workflow macro + Compile-time validation | L | `lib/hephaestus/core/workflow.ex` (modify) | task-001 |
| [task-005](task-005.md) | Storage behaviour + Storage.ETS | M | `lib/hephaestus/runtime/{storage.ex,storage/ets.ex}` | task-001 |

### Wave 2 — Engine funcional
| Task | Title | Effort | Files | Depends on |
|------|-------|--------|-------|------------|
| [task-004](task-004.md) | Engine funcional (advance, execute_step, complete_step, resume) | L | `lib/hephaestus/core/engine.ex`, `test/support/{test_steps,test_workflows}.ex` | task-001, task-002, task-003 |

### Wave 3 — Runtime OTP
| Task | Title | Effort | Files | Depends on |
|------|-------|--------|-------|------------|
| [task-006](task-006.md) | Runner behaviour + Runner.Local | L | `lib/hephaestus/runtime/{runner.ex,runner/local.ex}` | task-004, task-005 |

### Wave 4 — Integração final
| Task | Title | Effort | Files | Depends on |
|------|-------|--------|-------|------------|
| [task-007](task-007.md) | Módulo de entrada (`use Hephaestus`) | M | `lib/hephaestus.ex` | task-005, task-006 |

## Dependency Graph

```
Wave 0:  task-001 ──┬──→ task-002 ──┐
                    ├──→ task-003 ──┼──→ task-004 ──→ task-006 ──→ task-007
                    └──→ task-005 ──┘                    ↑
                                    └────────────────────┘
         task-008 (independent)
```

```
task-001 ──→ task-002 ──→ task-004
task-001 ──→ task-003 ──→ task-004
task-001 ──→ task-005 ──→ task-006
task-004 ──→ task-006 ──→ task-007
task-005 ──→ task-006
task-005 ──→ task-007
task-008 (no dependents)
```

## File Conflict Check

| File | Tasks | Waves | Conflict? |
|------|-------|-------|-----------|
| `lib/hephaestus/core/workflow.ex` | task-001 (create), task-003 (modify) | 0, 1 | NO — different waves |
| `lib/hephaestus.ex` | task-007 (modify) | 4 | NO — single task |

All other files are touched by exactly one task. **No file conflicts detected.**

## Balance Check

| Wave | Tasks | Effort range | Balanced? |
|------|-------|-------------|-----------|
| 0 | task-001 (M), task-008 (S) | S-M | YES — task-008 is trivial but independent, no reason to delay |
| 1 | task-002 (M), task-003 (L), task-005 (M) | M-L | YES — task-003 is bigger but not 3x |
| 2 | task-004 (L) | L | YES — single task, bottleneck unavoidable (needs all Wave 1) |
| 3 | task-006 (L) | L | YES — single task, needs engine + storage |
| 4 | task-007 (M) | M | YES — single task, final integration |

---

## Correction Tasks (Post-Review)

### Wave 5 — Core Engine fix
| Task | Title | Effort | Files | Depends on |
|------|-------|--------|-------|------------|
| [task-009](task-009.md) | Refactor Engine.advance/1 para expor active_steps ao Runtime | L | `lib/hephaestus/core/engine.ex`, `test/hephaestus/core/engine_test.exs` | task-004 |

### Wave 6 — Runtime fix + EventWorkflow (paralelo)
| Task | Title | Effort | Files | Depends on |
|------|-------|--------|-------|------------|
| [task-010](task-010.md) | Refactor Runner.Local para usar Engine.advance/1 | L | `lib/hephaestus/runtime/runner/local.ex`, `test/hephaestus/runtime/runner/local_test.exs` | task-009 |
| [task-011](task-011.md) | EventWorkflow + testes end-to-end WaitForEvent | M | `test/support/test_workflows.ex`, `test/hephaestus/core/engine_test.exs`, `test/hephaestus/runtime/runner/local_test.exs` | task-009 |

### Wave 7 — Resiliência e edge cases (paralelo)
| Task | Title | Effort | Files | Depends on |
|------|-------|--------|-------|------------|
| [task-012](task-012.md) | Crash recovery do Runner.Local | M | `lib/hephaestus/runtime/runner/local.ex`, `test/hephaestus/runtime/runner/local_test.exs` | task-010, task-011 |
| [task-013](task-013.md) | Testes negativos, concorrência e assertions robustas | M | `test/hephaestus/runtime/storage/ets_test.exs`, `test/hephaestus/core/engine_test.exs`, `test/support/test_workflows.ex` | task-010, task-011 |

## Correction Dependency Graph

```
task-009 (engine fix) ──┬──→ task-010 (runner fix) ──┬──→ task-012 (crash recovery)
                        └──→ task-011 (event tests) ──┤
                                                      └──→ task-013 (edge cases)
```

## File Conflict Check (Corrections)

| File | Tasks | Waves | Conflict? |
|------|-------|-------|-----------|
| `lib/hephaestus/runtime/runner/local.ex` | task-010 (modify), task-012 (modify) | 6, 7 | NO — different waves |
| `test/hephaestus/runtime/runner/local_test.exs` | task-010, task-011, task-012 | 6, 6, 7 | POTENTIAL in wave 6 |
| `test/hephaestus/core/engine_test.exs` | task-009, task-011, task-013 | 5, 6, 7 | NO — different waves |
| `test/support/test_workflows.ex` | task-011, task-013 | 6, 7 | NO — different waves |

**Mitigação Wave 6:** task-010 modifica runner tests, task-011 adiciona novos tests ao mesmo arquivo. task-010 foca em ajustar testes existentes, task-011 adiciona novos describe blocks. Risco baixo se ambos forem aditivos.

## Notes

- Waves 0-4: implementação original (DONE — 97 testes, 0 falhas)
- Waves 5-7: correções da review (PENDING)
- Wave 5 é sequencial (engine fix é pré-requisito de tudo)
- Wave 6 tem paralelismo: runner fix + event tests
- Wave 7 tem paralelismo: crash recovery + edge cases
- Task-010 e task-011 compartilham um test file na Wave 6 — risco baixo, ambas aditivas
