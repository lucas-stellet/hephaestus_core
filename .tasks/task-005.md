# Task 005: Storage behaviour + Storage.ETS

**Wave**: 1 | **Effort**: M
**Depends on**: task-001
**Blocks**: task-006, task-007

## Objective

Definir o behaviour de Storage e implementar o adapter ETS. O storage persiste instâncias de workflow, configurado no módulo de entrada. Implementação ETS é um GenServer que gerencia tabela `:set` com CRUD e queries.

## Files

**Create:** `lib/hephaestus/runtime/storage.ex` — behaviour definition
**Create:** `lib/hephaestus/runtime/storage/ets.ex` — ETS implementation (GenServer)
**Create:** `test/hephaestus/runtime/storage/ets_test.exs`
**Read:** `lib/hephaestus/core/instance.ex` — Instance struct armazenada

## Requirements

- Behaviour callbacks: `get/1` → `{:ok, Instance.t()} | {:error, :not_found}`, `put/1` → `:ok`, `delete/1` → `:ok`, `query/1` → `[Instance.t()]`
- Storage.ETS é GenServer gerenciando tabela `:set` nomeada
- put/1 usa instance.id como key, aceita overwrite
- delete/1 retorna :ok mesmo se não existir
- query/1 aceita keyword list de filtros: `status:`, `workflow:`
- query sem filtros retorna todas instâncias
- GenServer aceita opção `name:` para permitir múltiplas instâncias em testes
- TDD: ver skeletons em .compozy/tasks/hephaestus-core/task_05.md

## Done when

- [ ] Behaviour Storage definido com callbacks tipados
- [ ] Storage.ETS funciona como GenServer nomeado
- [ ] CRUD (put, get, delete) funciona
- [ ] Query com filtros por status e workflow funciona
- [ ] Query sem filtros retorna tudo
- [ ] Todos os testes passando
- [ ] Coverage >=80%
