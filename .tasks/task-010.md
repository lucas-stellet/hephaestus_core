# Task 010: Refactor Runner.Local para usar Engine primitives

**Wave**: 6 | **Effort**: L
**Depends on**: task-009
**Blocks**: task-012

## Objective

O Runner.Local reimplementa lógica de orquestração internamente (ensure_started, maybe_complete, activate_transitions, execute_single_step) em vez de usar as primitivas públicas do Engine refatorado na task-009. Além disso, chama `Engine.resume/2` que foi removido. O Runner deve delegar ao Engine e usar suas 6 primitivas: advance/1, execute_step/2, complete_step/4, activate_transitions/3, check_completion/1, resume_step/3.

<critical>
- ALWAYS READ the PRD and TechSpec before starting
- REFERENCE TECHSPEC for implementation details — do not duplicate here
- FOCUS ON "WHAT" — describe what needs to be accomplished, not how
- TESTS REQUIRED — every task MUST include tests in deliverables
</critical>

<requirements>
**handle_continue(:advance) — linhas 88-116:**
- DEVE chamar Engine.advance(instance) e branchar no status retornado
- Quando {:ok, %{status: :completed}} → persistir e parar GenServer
- Quando {:ok, %{status: :waiting}} → persistir e {:noreply, state}
- Quando {:ok, %{status: :running}} com active_steps → persistir e {:noreply, state, {:continue, :execute_active}}
- Ref TechSpec linhas 389-408
- REMOVER: ensure_started/1 (linhas 230-241) — Engine.advance/1 já faz isso
- REMOVER: execute_single_step/2 (linhas 192-222) — unificar com handle_continue(:execute_active)
- REMOVER: o branch de case por MapSet.size (linhas 95-116) — Engine.advance já retorna o status correto

**handle_continue(:execute_active) — linhas 118-156:**
- DEVE iterar instance.active_steps via Task.Supervisor.async_nolink
- Para cada step: chamar Engine.execute_step(instance, step_def)
- Para cada resultado {:ok, event} ou {:ok, event, ctx}: chamar Engine.complete_step + Engine.activate_transitions
- Para {:async}: marcar step como waiting, NÃO remover de active_steps
- Após processar todos: chamar Engine.check_completion(instance)
- REMOVER: activate_transitions/3 privado (linhas 251-262) — usar Engine.activate_transitions/3 público
- REMOVER: maybe_complete/1 privado (linhas 243-249) — usar Engine.check_completion/1 público
- REMOVER: maybe_activate_step/2 privado (linhas 264-272) — está dentro do Engine
- Ref TechSpec linhas 412-442

**handle_cast({:resume, event}) — linha 159-166:**
- DEVE chamar Engine.resume_step(instance, instance.current_step, event) em vez de Engine.resume/2
- Ref TechSpec linhas 444-448
- A chamada a Engine.resume/2 na linha 162 é o que causa a falha — Engine.resume/2 foi removido na task-009

**handle_info({:scheduled_resume, step_ref}) — linhas 168-180:**
- DEVE chamar Engine.resume_step(instance, step_ref, "timeout") em vez de Engine.resume/2
- A chamada a Engine.resume/2 na linha 172 é o que causa a falha
- REMOVER: o guard `current_step: step_ref` na linha 169 — resume_step/3 já recebe step_ref explícito
- Ref TechSpec linhas 450-453

**Locator table ETS global — linhas 14, 46, 57, 187-189, 316-345:**
- REMOVER: @locator_table, put_locator, get_locator, delete_locator, ensure_locator_table
- REMOVER: chamadas a put_locator (linha 46) e delete_locator (linhas 57, 188)
- lookup_instance/1 (linhas 303-310) DEVE usar o registry passado via opts/state em vez do locator
- O state DEVE incluir :registry para que lookup_instance funcione
- start_link/1 e init/1 DEVEM propagar registry pro state

**Funções privadas que DEVEM ser removidas (já existem no Engine):**
- ensure_started/1 (linhas 230-241)
- maybe_complete/1 (linhas 243-249)
- activate_transitions/3 (linhas 251-262)
- maybe_activate_step/2 (linhas 264-272)
- execute_single_step/2 (linhas 192-222)
</requirements>

<constraints>
- Runner NÃO reimplementa lógica que pertence ao Engine
- Runner NÃO tem ensure_started, maybe_complete, activate_transitions, maybe_activate_step
- Runner usa SOMENTE as primitivas públicas do Engine: advance, execute_step, complete_step, activate_transitions, check_completion, resume_step
- Runner NÃO chama Engine.resume/2 (removido na task-009) — usa Engine.resume_step/3
- Runner NÃO tem locator table ETS global — resolve registry via state
</constraints>

## Subtasks
- [ ] 10.1 Adicionar :registry ao state do GenServer (propagar de start_link/init)
- [ ] 10.2 Refatorar handle_continue(:advance) para usar Engine.advance/1
- [ ] 10.3 Refatorar handle_continue(:execute_active) para usar Engine.execute_step + complete_step + activate_transitions + check_completion
- [ ] 10.4 Corrigir handle_cast({:resume}) para usar Engine.resume_step/3
- [ ] 10.5 Corrigir handle_info({:scheduled_resume}) para usar Engine.resume_step/3
- [ ] 10.6 Remover locator table (put_locator, get_locator, delete_locator, ensure_locator_table, @locator_table)
- [ ] 10.7 Refatorar lookup_instance/1 para usar registry do state — precisará receber registry como parâmetro ou módulo-level
- [ ] 10.8 Remover funções privadas duplicadas: ensure_started, maybe_complete, activate_transitions, maybe_activate_step, execute_single_step

## Implementation Details

### Relevant Files
- `lib/hephaestus/runtime/runner/local.ex` — refatorar: linhas 88-116 (advance), 118-156 (execute_active), 159-166 (resume cast), 168-180 (scheduled_resume), 192-272 (remover privadas duplicadas), 316-345 (remover locator)

### Dependent Files
- `lib/hephaestus/core/engine.ex` — Engine refatorado (task-009) com 6 primitivas públicas. NÃO modificar
- `test/hephaestus/runtime/runner/local_test.exs` — testes existentes devem continuar passando
- `test/hephaestus/entry_module_test.exs` — testes end-to-end devem voltar a passar

### Related ADRs
- [ADR-001: Arquitetura do Hephaestus Core](../adrs/adr-001.md) — Runner é boundary, Engine é core puro
- [ADR-003: Runner como adapter](../adrs/adr-003.md) — Runner encapsula execução, Engine fornece primitivas

### Boundary Contract
- **Este task consome:** Engine com 6 primitivas: advance/1, execute_step/2, complete_step/4, activate_transitions/3, check_completion/1, resume_step/3
- **Este task produz:** Runner.Local limpo que delega ao Engine, sem lógica duplicada
- **Este task NÃO faz:** modificar o Engine, adicionar novas primitivas, mudar o behaviour Runner

## Deliverables
- Runner.Local refatorado usando Engine primitives
- Locator table removido
- Funções privadas duplicadas removidas
- Todos os 12 testes de runner/local_test.exs passando
- Todos os 3 testes de entry_module_test.exs passando (que atualmente falham)
- mix test completo passando com 0 falhas
- Test coverage >=80% **(REQUIRED)**

## Tests

Os testes existentes NÃO devem mudar — o comportamento externo do Runner é o mesmo. As 3 falhas atuais devem ser corrigidas pela refatoração.

- Testes que DEVEM voltar a passar (atualmente falhando):
  - [ ] Runner.LocalTest "resume/2 resumes paused instance and completes" (local_test.exs:72)
  - [ ] Runner.LocalTest "schedule_resume/3 resumes instance after delay" (local_test.exs:89)
  - [ ] EntryModuleTest "resume/2 resumes async workflow" (entry_module_test.exs:46)

- Testes que DEVEM continuar passando:
  - [ ] Linear workflow starts and completes
  - [ ] Persists instance in storage
  - [ ] Branch workflow follows correct branch
  - [ ] Async workflow pauses
  - [ ] Resume returns error for nonexistent
  - [ ] Parallel workflow fan-out/fan-in
  - [ ] GenServer stops after completion
  - [ ] Registers in Registry while running
  - [ ] Entry module start_instance, parallel workflow

## Success Criteria
- mix test: 0 falhas (todas as 97+ testes passando, incluindo as 3 atualmente falhando)
- 0 warnings de Engine.resume/2
- Runner.Local não tem nenhuma função duplicada do Engine
- Runner.Local não tem locator table ETS
- Runner.Local usa exclusivamente Engine.advance/1 em handle_continue(:advance)
