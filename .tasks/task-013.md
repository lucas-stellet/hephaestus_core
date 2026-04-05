# Task 013: Testes negativos, concorrência e assertions robustas

**Wave**: 2 | **Effort**: M
**Depends on**: task-010, task-011
**Blocks**: none

## Objective

Preencher os gaps de teste identificados na review: acesso concorrente ao Storage.ETS, testes negativos para APIs do Runner, assertions mais robustas nos testes de runtime, e cobertura de edge cases do Engine.

## Files

**Modify:** `test/hephaestus/runtime/storage/ets_test.exs` — testes de concorrência
**Modify:** `test/hephaestus/runtime/runner/local_test.exs` — testes negativos e assertions robustas
**Modify:** `test/hephaestus/core/engine_test.exs` — edge cases (transições sem match, etc)
**Modify:** `test/support/test_workflows.ex` — expandir ParallelWorkflow pra 3 branches

## Requirements

**Storage.ETS concorrente:**
- Múltiplos puts paralelos (Task.async_stream com N instâncias)
- Get/query enquanto writes acontecem
- Verificar consistência após operações concorrentes

**Runner negativos:**
- schedule_resume/3 com instância inexistente → {:error, :instance_not_found}
- resume/2 em instância já completed → comportamento definido
- start_instance com workflow inválido

**Engine edge cases:**
- Step emite evento sem transição definida → comportamento definido
- Fan-out com um branch async e outro sync → estados mistos
- ParallelWorkflow expandido pra 3 branches (A, B, C → Join)

**Assertions robustas:**
- Runtime tests devem verificar execution_history (ordem, conteúdo)
- Runtime tests devem verificar active_steps e completed_steps
- Runtime tests devem verificar context.steps com dados de cada step
- Substituir Process.sleep por polling helper com timeout

## Done when

- [ ] Storage.ETS: 3+ testes de concorrência passando
- [ ] Runner: testes negativos pra schedule_resume e resume
- [ ] Engine: teste de evento sem transição
- [ ] Engine: teste fan-out com branch misto (sync + async)
- [ ] ParallelWorkflow com 3 branches
- [ ] Runtime assertions verificam history, steps, context — não só status
- [ ] Todos os testes passando
- [ ] Coverage >=80%
