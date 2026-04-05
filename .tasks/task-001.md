# Task 001: Core data structs + StepDefinition protocol

**Wave**: 0 | **Effort**: M
**Depends on**: none
**Blocks**: task-002, task-003, task-004, task-005

## Objective

Criar a estrutura de diretórios da lib e implementar todas as structs do core funcional (Context, Instance, Workflow, Step, ExecutionEntry) junto com o protocolo StepDefinition. Fundação sobre a qual todo o resto é construído.

## Files

**Create:** `lib/hephaestus/core/context.ex` — struct do context (initial + steps)
**Create:** `lib/hephaestus/core/instance.ex` — struct da instância de workflow
**Create:** `lib/hephaestus/core/workflow.ex` — struct + behaviour do workflow
**Create:** `lib/hephaestus/core/step.ex` — struct genérica + impl do protocolo
**Create:** `lib/hephaestus/core/execution_entry.ex` — struct do histórico
**Create:** `lib/hephaestus/core/step_definition.ex` — protocolo StepDefinition
**Create:** `test/hephaestus/core/context_test.exs`
**Create:** `test/hephaestus/core/instance_test.exs`
**Create:** `test/hephaestus/core/step_test.exs`
**Create:** `test/hephaestus/core/step_definition_test.exs`
**Create:** `test/hephaestus/core/workflow_test.exs`
**Create:** `test/hephaestus/core/execution_entry_test.exs`

## Requirements

- Todas as structs usam `@enforce_keys` para campos obrigatórios
- `Context`: campos `initial` (map) e `steps` (map). Funções `new/1` e `put_step_result/3`
- `Instance`: campos id (binary UUID), workflow (module), status (atom), context (Context.t), active_steps (MapSet), completed_steps (MapSet), execution_history (list). Função `new/2` gera UUID. Status types: :pending, :running, :waiting, :completed, :failed
- `Workflow`: campos initial_step (atom) e steps (list). Callback `definition/0`
- `Step`: campos ref (atom, enforced), module (module, enforced), config (any, optional), transitions (map, optional)
- `ExecutionEntry`: campos step_ref (atom), event (string), timestamp (DateTime), context_updates (map, optional)
- Protocolo `StepDefinition` com funções: `ref/1`, `module/1`, `config/1`, `transitions/1`
- `Core.Step` implementa `StepDefinition`
- TDD: escrever testes primeiro, depois implementar. Ver skeletons em .compozy/tasks/hephaestus-core/task_01.md

## Done when

- [ ] Estrutura de diretórios criada (core/, runtime/, steps/, connectors/)
- [ ] 6 structs implementadas com @enforce_keys
- [ ] Protocolo StepDefinition definido e implementado para Core.Step
- [ ] Context.new/1 e Context.put_step_result/3 funcionam
- [ ] Instance.new/2 gera IDs únicos
- [ ] Todos os testes passando
- [ ] Coverage >=80%
