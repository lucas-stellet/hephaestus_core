# Task 011: Adicionar EventWorkflow e testes end-to-end de WaitForEvent

**Wave**: 1 | **Effort**: M
**Depends on**: task-009
**Blocks**: task-012

## Objective

WaitForEvent nunca é testado end-to-end. Criar o EventWorkflow de teste e adicionar cobertura no Engine e Runner.Local para o fluxo: step → wait_for_event → evento externo chega → resume → próximo step → end.

## Files

**Modify:** `test/support/test_workflows.ex` — adicionar EventWorkflow
**Modify:** `test/support/test_steps.ex` — adicionar WaitForEventStep de teste se necessário
**Modify:** `test/hephaestus/core/engine_test.exs` — testes engine com EventWorkflow
**Modify:** `test/hephaestus/runtime/runner/local_test.exs` — testes runtime com EventWorkflow
**Modify:** `test/hephaestus/entry_module_test.exs` — teste end-to-end via entry module

## Requirements

- EventWorkflow: A → WaitForEvent("payment_confirmed") → B → End
- Engine: advance até waiting, resume com "payment_confirmed", advance até completed
- Runner.Local: start_instance → waiting, resume(id, "payment_confirmed") → completed
- Entry module: end-to-end via MyApp.Hephaestus
- Testar resume com evento errado (se aplicável — definir comportamento)
- Testar resume em instância que não está waiting

## Done when

- [ ] EventWorkflow criado em test/support/test_workflows.ex
- [ ] Engine testa advance → waiting → resume("payment_confirmed") → completed
- [ ] Runner.Local testa start → waiting → resume → completed
- [ ] Entry module testa flow completo via API pública
- [ ] Todos os testes passando
- [ ] Coverage >=80%
