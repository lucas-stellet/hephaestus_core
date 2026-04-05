# Task 007: Módulo de entrada (`use Hephaestus`)

**Wave**: 4 | **Effort**: M
**Depends on**: task-005, task-006
**Blocks**: none

## Objective

Implementar a macro `use Hephaestus` que gera o módulo de entrada da app consumidora. Configura storage e runner, gera child_spec com supervision tree interna, e expõe API pública que delega pro runner. Pattern similar ao Ecto Repo.

## Files

**Modify:** `lib/hephaestus.ex` — macro __using__ com opções
**Create:** `test/hephaestus/entry_module_test.exs`
**Read:** `lib/hephaestus/runtime/runner.ex` — Runner behaviour
**Read:** `lib/hephaestus/runtime/runner/local.ex` — Runner.Local
**Read:** `lib/hephaestus/runtime/storage/ets.ex` — Storage.ETS
**Read:** `test/support/test_workflows.ex` — workflows de teste reutilizados

## Requirements

- `use Hephaestus, storage: Module, runner: Module` gera módulo com API
- Defaults: storage = Hephaestus.Runtime.Storage.ETS, runner = Hephaestus.Runtime.Runner.Local
- Gera child_spec/1 que starta Supervisor com filhos: Registry, DynamicSupervisor, TaskSupervisor, Storage
- Nomes de processos derivados do módulo: `MyApp.Hephaestus.Registry`, `.DynamicSupervisor`, `.TaskSupervisor`, `.Storage`
- Gera `start_instance/2` e `resume/2` delegando pro runner com opts corretos
- O módulo é adicionável na supervision tree: `children = [MyApp.Hephaestus]`
- Testes end-to-end: workflow completo via módulo de entrada
- TDD: ver skeletons em .compozy/tasks/hephaestus-core/task_07.md

## Done when

- [ ] `use Hephaestus` gera módulo funcional
- [ ] Supervision tree starta todos filhos
- [ ] start_instance/2 e resume/2 funcionam
- [ ] Linear workflow completa end-to-end
- [ ] Async workflow resume end-to-end
- [ ] Parallel workflow fan-out/fan-in end-to-end
- [ ] Todos os testes passando
- [ ] Coverage >=80%
