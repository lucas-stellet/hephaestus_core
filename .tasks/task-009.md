# Task 009: Refactor Engine.advance/1 para expor active_steps ao Runtime

**Wave**: 0 | **Effort**: L
**Depends on**: none
**Blocks**: task-010

## Objective

O Engine.advance/1 atualmente executa steps internamente em loop sequencial. Isso impede o Runtime de fazer fan-out paralelo via Task.Supervisor. O engine deve retornar a instância com active_steps populado para o Runtime decidir como executar, em vez de executar tudo internamente.

## Files

**Modify:** `lib/hephaestus/core/engine.ex` — reestruturar advance/1, separar ativação de execução
**Modify:** `test/hephaestus/core/engine_test.exs` — ajustar testes para novo comportamento
**Modify:** `test/support/test_workflows.ex` — adicionar EventWorkflow
**Modify:** `test/support/test_steps.ex` — adicionar step de WaitForEvent test

## Requirements

- `advance/1` em instância :pending deve: mudar status pra :running, ativar initial_step em active_steps, retornar `{:ok, instance}` SEM executar o step
- `advance/1` em instância :running com active_steps deve: executar os steps ativos sequencialmente (no core puro), resolver transições, ativar próximos steps. Retornar quando encontrar :async, completar, ou falhar
- `execute_step/2` deve permanecer como primitiva chamável externamente pelo Runtime
- `complete_step/4` deve permanecer como primitiva chamável externamente pelo Runtime
- O Runtime deve poder escolher: chamar advance (sequencial) ou iterar active_steps + execute_step + complete_step (paralelo)
- Remover `DateTime.utc_now()` do complete_step — receber timestamp como parâmetro ou deixar pro chamador
- Adicionar `resume_step/3` que resume por step_ref específico (não só current_step)

## Done when

- [ ] Engine.advance/1 não executa steps em :pending — só ativa initial_step
- [ ] Engine tem resume_step/3 com step_ref
- [ ] complete_step não chama DateTime.utc_now() internamente
- [ ] Engine permanece puro funcional (zero side-effects)
- [ ] Todos os testes existentes passam (ajustados pro novo comportamento)
- [ ] Novos testes para resume_step/3
- [ ] Coverage >=80%
