# Hephaestus v2 API — Task Tracking

## Baseline

- 118 tests passing
- Elixir 1.15+ / OTP 26+

## Tasks

| # | Task | Depende de | Status |
|---|------|-----------|--------|
| 01 | [Adicionar libgraph](task-01-libgraph-dependency.md) | — | completed |
| 02 | [Step behaviour: events/0 + step_key/0](task-02-step-behaviour.md) | — | completed |
| 03 | [Built-in steps: events/0](task-03-builtin-steps.md) | 02 | completed |
| 04 | [Instance step_configs + ExecutionEntry types](task-04-data-structs.md) | — | completed |
| 05 | [Remover Step struct + StepDefinition protocol](task-05-remove-structs.md) | 04 | completed |
| 06 | [Workflow macro: edge extraction + libgraph](task-06-workflow-macro.md) | 01, 02, 05 | completed |
| 07 | [Engine: nova API](task-07-engine.md) | 04, 05, 06 | completed |
| 08 | [Runner + entry module: types](task-08-runner-entry.md) | 07 | completed |
| 09 | [Migrar tests v1 para v2](task-09-update-v1-tests.md) | 02-08 | completed |
| 10 | [Unit tests engine v2](task-10-unit-tests-engine.md) | 06, 07 | completed |
| 11 | [Integration tests runtime](task-11-integration-tests.md) | 08, 09, 10 | pending |

## Grafo de dependencias

```
01 (libgraph) ──────────────────┐
02 (step behaviour) ────────────┤
                                ├── 06 (workflow macro) ── 07 (engine) ── 08 (runner) ── 09 (migrar tests v1)
03 (builtin steps) ◄── 02       │                              │                              │
04 (data structs) ── 05 (remove)┘                              │                              │
                                                               ├── 10 (unit tests engine) ────┤
                                                               │                              │
                                                               └──────────────────────────── 11 (integration)
```

## Ponto de nao-retorno

Apos task 05 (remocao de step.ex e step_definition.ex), o projeto NAO compila ate tasks 06 e 07 estarem completas. Tasks 05-07 devem ser um unico commit.

## Criterio de sucesso final

- `mix test` — todos os testes passando (v2 novos + v1 migrados)
- Zero referencias a `%Step{}`, `StepDefinition`, `definition/0`, ou eventos string
- `mix compile --warnings-as-errors` sem warnings
