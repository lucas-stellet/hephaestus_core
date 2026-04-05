# Task 011: EventWorkflow + testes end-to-end WaitForEvent

**Wave**: 6 | **Effort**: M
**Depends on**: task-009
**Blocks**: task-012, task-013

## Objective

O step WaitForEvent nunca é testado end-to-end. Existe o módulo `Hephaestus.Steps.WaitForEvent` (lib/hephaestus/steps/wait_for_event.ex) que retorna `{:async}`, e existe `Hephaestus.Test.AsyncStep` (test/support/test_steps.ex:28-33) que faz o mesmo — mas nenhum workflow de teste exercita o fluxo completo: step → wait_for_event → evento externo chega → resume_step → próximo step → end.

O AsyncWorkflow (test/support/test_workflows.ex:63-79) usa `Hephaestus.Test.AsyncStep` genérico para testar wait+timeout. Precisamos de um EventWorkflow que teste o resume por evento externo nomeado, validando que `Engine.resume_step/3` e `Runner.Local.resume/2` funcionam corretamente para esse caso.

<critical>
- ALWAYS READ the PRD and TechSpec before starting
- REFERENCE TECHSPEC for implementation details — do not duplicate here
- FOCUS ON "WHAT" — describe what needs to be accomplished, not how
- TESTS REQUIRED — every task MUST include tests in deliverables
</critical>

<requirements>
**Novo test step — test/support/test_steps.ex:**
- Adicionar `Hephaestus.Test.WaitForEventStep` que usa o built-in `Hephaestus.Steps.WaitForEvent` ou simplesmente retorna `{:async}` (o comportamento é idêntico ao AsyncStep, mas o workflow terá transição com nome de evento específico em vez de "timeout")

**Novo workflow — test/support/test_workflows.ex:**
- Adicionar `Hephaestus.Test.EventWorkflow` com shape: `:step_a → :wait_for_event → :step_b → :finish`
- `:step_a` usa PassStep, transição `"done" => :wait_for_event`
- `:wait_for_event` usa AsyncStep (ou WaitForEventStep), transição `"payment_confirmed" => :step_b` (evento nomeado, NÃO "timeout")
- `:step_b` usa PassWithContextStep, transição `"done" => :finish`
- `:finish` usa Hephaestus.Steps.End
- O evento de resume é "payment_confirmed" — nome específico para diferenciar do "timeout" do AsyncWorkflow

**Testes no Engine — test/hephaestus/core/engine_test.exs:**
- Adicionar describe "advance/1 — event workflow" com testes que usam as primitivas manuais (como o padrão estabelecido na task-009)
- Teste 1: advance → running com :step_a ativo → executar step_a → complete → activate_transitions → advance → executar wait_for_event → {:async} → instância tem :wait_for_event em active_steps
- Teste 2: a partir do estado waiting, chamar Engine.resume_step(instance, :wait_for_event, "payment_confirmed") → instância :running com :step_b em active_steps
- Teste 3: fluxo completo manual: advance → execute todos steps um a um até completed, usando "payment_confirmed" como evento de resume

**Testes no Runner.Local — test/hephaestus/runtime/runner/local_test.exs:**
- Adicionar describe "start_instance/3 - event workflow"
- Teste 1: start_instance(EventWorkflow) → Process.sleep → status deve ser :waiting (parou no wait_for_event)
- Teste 2: start_instance → sleep → resume(id, "payment_confirmed") → sleep → status :completed
- Teste 3: verificar que completed_steps inclui :step_a, :wait_for_event, :step_b, :finish
- Teste 4: verificar que context.steps[:step_b] tem %{processed: true}

**Testes no Entry Module — test/hephaestus/entry_module_test.exs:**
- Adicionar teste end-to-end: TestHephaestus.start_instance(EventWorkflow) → resume → completed
</requirements>

<constraints>
- NÃO modificar lib/hephaestus/core/engine.ex — o Engine já suporta resume_step/3
- NÃO modificar lib/hephaestus/runtime/runner/local.ex — o Runner já suporta resume/2 → resume_step/3
- NÃO modificar nenhum teste existente — apenas ADICIONAR novos describe blocks
- Os novos testes do Engine DEVEM seguir o padrão de primitivas manuais (advance → execute_step → complete_step → activate_transitions) estabelecido nos testes da task-009, usando a helper `run_step/3` se existir
</constraints>

## Subtasks
- [ ] 11.1 Adicionar EventWorkflow em test/support/test_workflows.ex (após AsyncWorkflow, linha 79)
- [ ] 11.2 Adicionar testes Engine para event workflow em test/hephaestus/core/engine_test.exs (novo describe block)
- [ ] 11.3 Adicionar testes Runner.Local para event workflow em test/hephaestus/runtime/runner/local_test.exs (novo describe block)
- [ ] 11.4 Adicionar teste end-to-end no entry module em test/hephaestus/entry_module_test.exs (novo teste no describe existente)

## Implementation Details

### Relevant Files
- `test/support/test_workflows.ex` — adicionar EventWorkflow após linha 79
- `test/support/test_steps.ex` — opcionalmente adicionar WaitForEventStep (pode reusar AsyncStep)
- `test/hephaestus/core/engine_test.exs` — adicionar describe "advance/1 — event workflow"
- `test/hephaestus/runtime/runner/local_test.exs` — adicionar describe "start_instance/3 - event workflow"
- `test/hephaestus/entry_module_test.exs` — adicionar teste de event workflow

### Dependent Files
- `lib/hephaestus/core/engine.ex` — NÃO modificar, apenas chamar suas primitivas nos testes
- `lib/hephaestus/runtime/runner/local.ex` — NÃO modificar, apenas usar via start_instance/resume nos testes

### Related ADRs
- [ADR-001: Arquitetura do Hephaestus Core](../adrs/adr-001.md) — Engine puro + Runtime OTP

### Boundary Contract
- **Este task produz:** EventWorkflow de teste + cobertura end-to-end de WaitForEvent
- **Consumido por:** task-012 e task-013 podem reusar EventWorkflow nos seus testes
- **Este task NÃO faz:** modificar Engine, Runner, ou qualquer código de produção

## Deliverables
- EventWorkflow em test/support/test_workflows.ex
- Testes Engine: 3+ novos testes para event workflow
- Testes Runner: 4+ novos testes para event workflow
- Teste Entry Module: 1+ novo teste end-to-end
- mix test completo passando com 0 falhas
- Unit tests com 80%+ coverage **(REQUIRED)**

## Tests

- Engine (unit, sem processos):
  - [ ] advance EventWorkflow → :running → executar step_a → complete → activate → :wait_for_event ativo
  - [ ] executar wait_for_event → {:async} → step permanece em active_steps
  - [ ] resume_step(instance, :wait_for_event, "payment_confirmed") → :running, :step_b ativo
  - [ ] fluxo completo manual até :completed com "payment_confirmed" como evento

- Runner.Local (integration, com processos):
  - [ ] start_instance(EventWorkflow) → waiting (parou no wait_for_event)
  - [ ] start → waiting → resume(id, "payment_confirmed") → completed
  - [ ] verificar completed_steps inclui todos os steps
  - [ ] verificar context.steps[:step_b] tem dados corretos

- Entry Module (end-to-end):
  - [ ] TestHephaestus.start_instance(EventWorkflow) → resume → completed

- Test coverage target: >=80%

## Success Criteria
- mix test: 0 falhas
- EventWorkflow exercita o fluxo wait_for_event → evento externo → resume completo
- Engine, Runner e Entry Module todos têm cobertura para event-driven workflows
- Nenhum arquivo de produção modificado
