# Task 003: Workflow macro + Compile-time graph validation

**Wave**: 1 | **Effort**: L
**Depends on**: task-001
**Blocks**: task-004

## Objective

Implementar `use Hephaestus.Workflow` com `@before_compile` que valida o grafo do workflow em compile-time. Detectar ciclos, steps órfãos, targets inexistentes, refs duplicados. Computar `__predecessors__/1` e `__step__/1` para uso pelo engine.

## Files

**Modify:** `lib/hephaestus/core/workflow.ex` — adicionar macro __using__, __before_compile__, funções geradas
**Create:** `test/hephaestus/core/workflow_validation_test.exs`
**Read:** `lib/hephaestus/core/step_definition.ex` — protocolo usado na validação
**Read:** `lib/hephaestus/core/step.ex` — Step struct validada

## Requirements

- `use Hephaestus.Workflow` injeta `@behaviour Hephaestus.Core.Workflow` e `@before_compile`
- @before_compile chama `definition/0` do módulo e valida o grafo
- Validações: refs duplicados, initial_step inexistente, transition targets inexistentes, ciclos (DFS), steps não alcançáveis do initial_step, config como map solto (deve ser struct)
- Fan-out: transitions com lista de atoms são reconhecidas
- Gera `__predecessors__/1` — MapSet de refs que apontam pra cada step (grafo reverso)
- Gera `__step__/1` — retorna step definition por ref via protocolo
- Gera `__steps_map__/0` — converte lista de steps pra map indexado por ref
- Erros de compilação com mensagens descritivas (ex: "step :notify referenced in transitions but not defined in steps/0")
- TDD: ver skeletons em .compozy/tasks/hephaestus-core/task_03.md

## Done when

- [ ] use Hephaestus.Workflow funciona com callback definition/0
- [ ] Workflows válidos (linear, branch, fan-out) compilam
- [ ] Workflows inválidos levantam CompileError com mensagem clara
- [ ] __predecessors__/1 computa corretamente para fan-in
- [ ] __step__/1 e __steps_map__/0 funcionam
- [ ] Todos os testes passando
- [ ] Coverage >=80%
