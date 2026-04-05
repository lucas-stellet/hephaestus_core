# Task 004: Engine funcional (advance, execute_step, complete_step, resume)

**Wave**: 2 | **Effort**: L
**Depends on**: task-001, task-002, task-003
**Blocks**: task-006

## Objective

Implementar o engine funcional puro — coração do Hephaestus. Funções que transformam dados sem side-effects: executar steps, resolver transições, gerenciar fan-out/fan-in, propagar context. Testável em IEx sem processos OTP.

## Files

**Create:** `lib/hephaestus/core/engine.ex` — funções puras do engine
**Create:** `test/support/test_steps.ex` — steps de teste (PassStep, BranchStep, AsyncStep, FailStep)
**Create:** `test/support/test_workflows.ex` — workflows de teste (Linear, Branch, Parallel, Async)
**Create:** `test/hephaestus/core/engine_test.exs`
**Read:** `lib/hephaestus/core/instance.ex` — Instance manipulada
**Read:** `lib/hephaestus/core/context.ex` — Context.put_step_result
**Read:** `lib/hephaestus/core/step_definition.ex` — protocolo para dispatch
**Read:** `lib/hephaestus/core/workflow.ex` — __step__, __predecessors__

## Requirements

- `advance/1` executa steps ativos sequencialmente até pausar, completar ou falhar
- `advance/1` ativa initial_step quando instância está :pending
- `execute_step/2` despacha via protocolo StepDefinition, chama module.execute/3
- `complete_step/4` marca step como completado, move de active_steps pra completed_steps, chama Context.put_step_result/3, adiciona ExecutionEntry
- Fan-out: transição pra lista de atoms ativa todos os targets em active_steps
- Fan-in: step só é ativado quando TODOS predecessores estão em completed_steps (MapSet.subset?)
- `resume/2` retoma instância pausada em :waiting — move step de active para permite re-advance
- Status transitions: :pending → :running → :waiting | :completed | :failed
- Engine NÃO tem side-effects (sem Logger, sem processos, sem IO)
- Test support files criam steps e workflows reutilizáveis pelas tasks 006 e 007
- TDD: ver skeletons em .compozy/tasks/hephaestus-core/task_04.md

## Done when

- [ ] Linear workflow executa todos steps e completa
- [ ] Branch workflow segue caminho correto
- [ ] Fan-out ativa todos targets paralelos
- [ ] Fan-in espera todos predecessores
- [ ] Context namespaced por step ref via put_step_result
- [ ] Async step pausa com status :waiting
- [ ] Resume retoma e continua execução
- [ ] Execution history registra todos steps
- [ ] Error handling retorna {:error, reason}
- [ ] Todos os testes passando
- [ ] Coverage >=80%
