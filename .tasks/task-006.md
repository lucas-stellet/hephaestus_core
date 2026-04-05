# Task 006: Runner behaviour + Runner.Local

**Wave**: 3 | **Effort**: L
**Depends on**: task-004, task-005
**Blocks**: task-007

## Objective

Definir o behaviour de Runner e implementar Runner.Local — módulo único que implementa o behaviour e é GenServer. Cada instância de workflow vira um processo via DynamicSupervisor + Registry. Delega execução pro Engine funcional e usa Task.Supervisor pra fan-out.

## Files

**Create:** `lib/hephaestus/runtime/runner.ex` — behaviour definition
**Create:** `lib/hephaestus/runtime/runner/local.ex` — Runner.Local (behaviour + GenServer)
**Create:** `test/hephaestus/runtime/runner/local_test.exs`
**Read:** `lib/hephaestus/core/engine.ex` — Engine chamado pelo GenServer
**Read:** `lib/hephaestus/runtime/storage/ets.ex` — Storage usado para persistir
**Read:** `test/support/test_workflows.ex` — workflows de teste reutilizados

## Requirements

- Behaviour callbacks: `start_instance/3`, `resume/2`, `schedule_resume/3`
- Runner.Local implementa `@behaviour Hephaestus.Runtime.Runner` + `use GenServer` num módulo
- Registra via `{:via, Registry, {registry_name, instance_id}}`
- start_instance: cria Instance, persiste no Storage, starta GenServer via DynamicSupervisor
- init usa `{:continue, :advance}` pra começar execução
- handle_continue(:advance) chama Engine.advance e decide próximo estado
- handle_continue(:execute_active) usa Task.Supervisor.async_nolink pra fan-out paralelo
- handle_cast({:resume, event}) chama Engine.resume + continue :advance
- handle_info({:scheduled_resume, step_ref}) usa Engine.resume_step + continue :advance
- schedule_resume usa Process.send_after
- GenServer persiste no Storage após cada mudança
- GenServer para com {:stop, :normal} quando instância completa
- resume retorna {:error, :instance_not_found} se processo não existe
- Testes usam `async: false` e Process.sleep para sincronização
- TDD: ver skeletons em .compozy/tasks/hephaestus-core/task_06.md

## Done when

- [ ] Behaviour Runner definido
- [ ] Runner.Local funciona como behaviour + GenServer
- [ ] Linear workflow starta e completa
- [ ] Async workflow pausa e resume funciona
- [ ] schedule_resume funciona com delay
- [ ] Fan-out/fan-in funciona com Task.Supervisor
- [ ] GenServer para após completion
- [ ] Registra/desregistra no Registry
- [ ] Todos os testes passando
- [ ] Coverage >=80%
