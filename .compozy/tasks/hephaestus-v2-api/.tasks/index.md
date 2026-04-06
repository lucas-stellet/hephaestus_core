# Task Plan: Hephaestus v2 API

> Generated from: .compozy/tasks/hephaestus-v2-api/_techspec.md
> Total tasks: 11 | Execution: sequencial

## Ordem de execucao

| # | Task | Effort | Commit? |
|---|------|--------|---------|
| 01 | [Adicionar libgraph](../task-01-libgraph-dependency.md) | S | sim |
| 02 | [Step behaviour: events/0 + step_key/0](../task-02-step-behaviour.md) | S | sim |
| 03 | [Built-in steps: events/0](../task-03-builtin-steps.md) | S | sim |
| 04 | [Instance step_configs + ExecutionEntry types](../task-04-data-structs.md) | S | sim |
| 05 | [Remover Step struct + StepDefinition protocol](../task-05-remove-structs.md) | S | NAO — projeto nao compila |
| 06 | [Workflow macro: edge extraction + libgraph](../task-06-workflow-macro.md) | XL | NAO — projeto nao compila |
| 07 | [Engine: nova API](../task-07-engine.md) | M | sim (commit unico 05+06+07) |
| 08 | [Runner + entry module: types](../task-08-runner-entry.md) | S | sim |
| 09 | [Migrar tests v1 para v2](../task-09-update-v1-tests.md) | M | sim |
| 10 | [Unit tests engine v2](../task-10-unit-tests-engine.md) | M | sim |
| 11 | [Integration tests runtime](../task-11-integration-tests.md) | M | sim |

## Commits

- Tasks 01-04: um commit por task (projeto compila e testes passam a cada passo)
- Tasks 05-06-07: **commit unico** (projeto nao compila entre elas)
- Tasks 08-11: um commit por task

## Baseline

- 118 tests passing
- Elixir 1.15+ / OTP 26+

## Criterio de sucesso final

- `mix test` — todos os testes passando
- Zero referencias a `%Step{}`, `StepDefinition`, `definition/0`, ou eventos string
- `mix compile --warnings-as-errors` sem warnings
