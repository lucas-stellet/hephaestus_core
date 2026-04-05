# Task 010: Refactor Runner.Local para usar Engine.advance/1 como orquestrador

**Wave**: 1 | **Effort**: L
**Depends on**: task-009
**Blocks**: task-012

## Objective

O Runner.Local atualmente reimplementa a lógica de orquestração internamente em vez de delegar pro Engine. handle_continue(:advance) deve chamar Engine.advance/1 e reagir ao status retornado. handle_continue(:execute_active) deve usar Engine.execute_step/2 e Engine.complete_step/4 como primitivas. Remover o locator table ETS global extra.

## Files

**Modify:** `lib/hephaestus/runtime/runner/local.ex` — reestruturar para delegar ao Engine
**Modify:** `test/hephaestus/runtime/runner/local_test.exs` — ajustar e adicionar testes

## Requirements

- `handle_continue(:advance)` DEVE chamar `Engine.advance(state.instance)` e branchar no status retornado (:completed, :waiting, :running, :failed)
- `handle_continue(:execute_active)` DEVE iterar active_steps via Task.Supervisor.async_nolink, chamando Engine.execute_step/2 pra cada, e Engine.complete_step/4 ao receber resultado
- `schedule_resume/3` DEVE ser roteado via GenServer.call, não via Process.send_after externo direto
- `handle_info({:scheduled_resume, step_ref})` DEVE usar Engine.resume_step/3 com step_ref (não resume/2 genérico)
- Remover locator table ETS global — usar opts passados na inicialização para resolver Registry name
- Manter a interface Runner behaviour inalterada (start_instance/3, resume/2, schedule_resume/3)

## Done when

- [ ] handle_continue(:advance) delega ao Engine.advance/1
- [ ] handle_continue(:execute_active) usa Task.Supervisor + Engine primitives
- [ ] schedule_resume roteado via GenServer callback
- [ ] resume usa Engine.resume_step/3 com step_ref
- [ ] Locator table ETS removido
- [ ] Todos os testes existentes passam
- [ ] Coverage >=80%
