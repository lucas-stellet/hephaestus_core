# Task 009: Refactor Engine — separar ativação de execução

**Wave**: 5 | **Effort**: L
**Depends on**: task-004
**Blocks**: task-010, task-011

## Objective

O Engine atual (engine.ex:53-82) executa steps internamente num loop recursivo (`do_advance → execute_step → complete_step → do_advance`). Segundo o TechSpec (Data Flow linhas 93-98), o Engine só deve **ativar** steps em `active_steps` e retornar. Quem **executa** os steps é o Runner. Essa separação é o que permite ao Runner.Local fazer fan-out paralelo via Task.Supervisor.

<critical>
- ALWAYS READ the PRD and TechSpec before starting
- REFERENCE TECHSPEC for implementation details — do not duplicate here
- FOCUS ON "WHAT" — describe what needs to be accomplished, not how
- TESTS REQUIRED — every task MUST include tests in deliverables
</critical>

<requirements>
- advance/1 em instância :pending DEVE: ativar initial_step em active_steps, mudar status pra :running, retornar {:ok, instance} SEM executar o step. (Ref: engine.ex:84-93 ensure_started — manter essa lógica, remover a chamada a do_advance)
- advance/1 em instância :running com active_steps NÃO vazio DEVE: retornar {:ok, instance} imediatamente, SEM executar nenhum step. Os steps ficam em active_steps pro Runner executar
- advance/1 em instância :running com active_steps vazio DEVE: marcar status :completed, retornar {:ok, instance}. (Ref: engine.ex:97-103 maybe_complete)
- advance/1 em instância :waiting DEVE: retornar {:ok, instance} sem mudanças
- execute_step/2 DEVE permanecer como está (engine.ex:12-19) — é uma primitiva que o Runner chama externamente
- complete_step DEVE receber timestamp como parâmetro em vez de chamar DateTime.utc_now() internamente (engine.ex:26). Nova assinatura: complete_step/5 com timestamp, ou complete_step/4 onde o chamador monta o context_updates. Decisão: complete_step/4 permanece mas NÃO cria ExecutionEntry — o chamador é responsável por adicionar ao execution_history
- activate_transitions/3 (engine.ex:112-123) DEVE se tornar função PÚBLICA. O Runner chama após complete_step: Engine.activate_transitions(instance, step_ref, event)
- maybe_complete/1 (engine.ex:97-103) DEVE se tornar função PÚBLICA renomeada pra check_completion/1. O Runner chama após processar todos active_steps
- Adicionar resume_step/3 que aceita step_ref explícito: resume_step(instance, step_ref, event). Deve remover step_ref de active_steps, adicionar a completed_steps, e ativar transições. (Ref: TechSpec linha 452: Engine.resume_step(instance, step_ref, "timeout"))
- resume/2 atual (engine.ex:39-49) que usa current_step implícito DEVE ser removido ou delegado a resume_step/3
- do_advance/1 (engine.ex:51-82) DEVE ser REMOVIDO inteiramente — o loop recursivo de execução não pertence ao Engine
- next_active_step/1 (engine.ex:105-110) DEVE ser REMOVIDO — o Runner itera active_steps diretamente
- Engine DEVE permanecer puro: NENHUMA chamada a DateTime, Logger, IO, Process, ou qualquer side-effect
</requirements>

<constraints>
- Engine NÃO executa steps — só ativa/desativa em active_steps e completed_steps
- Engine NÃO decide paralelismo — o Runner decide se executa sequencial ou paralelo
- Engine NÃO gera timestamps — o chamador passa ou monta externamente
- Engine NÃO faz I/O de nenhum tipo
- Engine NÃO tem loop recursivo de execução — cada chamada a advance/1 faz UMA transição de estado e retorna
</constraints>

## Subtasks
- [ ] 9.1 Refatorar advance/1: remover chamada a do_advance, retornar instance com active_steps populado
- [ ] 9.2 Remover do_advance/1 e next_active_step/1
- [ ] 9.3 Tornar activate_transitions/3 pública
- [ ] 9.4 Tornar maybe_complete/1 pública como check_completion/1
- [ ] 9.5 Remover DateTime.utc_now() de complete_step — não criar ExecutionEntry internamente
- [ ] 9.6 Implementar resume_step/3 com step_ref explícito
- [ ] 9.7 Remover resume/2 (ou delegar a resume_step/3)
- [ ] 9.8 Ajustar todos os testes existentes do Engine pro novo comportamento

## Implementation Details

### Relevant Files
- `lib/hephaestus/core/engine.ex` — refatorar: remover linhas 51-82 (do_advance), 105-110 (next_active_step), modificar linhas 6-10 (advance), 21-37 (complete_step), 39-49 (resume), 112-123 (activate_transitions → pública)

### Dependent Files
- `test/hephaestus/core/engine_test.exs` — ajustar todos os testes: advance não executa mais, precisa chamar execute_step + complete_step + activate_transitions manualmente nos testes
- `test/support/test_steps.ex` — sem mudanças
- `test/support/test_workflows.ex` — sem mudanças

### Related ADRs
- [ADR-001: Arquitetura do Hephaestus Core](../adrs/adr-001.md) — Engine como core funcional puro, Runner como boundary

### Boundary Contract
- **Este task produz:** Engine com 6 primitivas públicas: advance/1 (ativação), execute_step/2 (execução), complete_step/4 (completar step), activate_transitions/3 (resolver próximos steps), check_completion/1 (verificar se terminou), resume_step/3 (retomar step específico)
- **Consumido por:** task-010 (Runner.Local) — o Runner orquestra chamando essas primitivas na ordem: advance → execute_step → complete_step → activate_transitions → check_completion
- **Este task NÃO faz:** loop de execução, decisão de paralelismo, persistência, I/O

## Deliverables
- Engine refatorado com primitivas públicas separadas
- do_advance e next_active_step removidos
- resume_step/3 implementado
- DateTime.utc_now() removido do Engine
- Unit tests ajustados e passando
- Unit tests com 80%+ coverage **(REQUIRED)**

## Tests

O padrão dos testes muda. Antes: `Engine.advance(instance)` retornava instância completa. Agora: precisa chamar as primitivas em sequência.

- Unit tests:
  - [ ] advance/1 em :pending → retorna :running com initial_step em active_steps, SEM executar
  - [ ] advance/1 em :running com active_steps → retorna :running imediatamente sem mudanças
  - [ ] advance/1 em :running com active_steps vazio → retorna :completed
  - [ ] advance/1 em :waiting → retorna :waiting sem mudanças
  - [ ] execute_step/2 — dispatch via protocolo, retorna resultado do step (sem mudanças)
  - [ ] complete_step/4 — move step de active pra completed, atualiza context, NÃO cria ExecutionEntry
  - [ ] activate_transitions/3 — ativa targets corretos, suporta fan-out (lista), respeita fan-in (predecessors)
  - [ ] check_completion/1 — retorna :completed quando active_steps vazio, mantém status quando não vazio
  - [ ] resume_step/3 — remove de active, adiciona a completed, ativa transições
  - [ ] resume_step/3 — funciona com step_ref específico (não depende de current_step)
  - [ ] Fluxo completo manual: advance → execute_step → complete_step → activate_transitions → check_completion (workflow linear)
  - [ ] Fluxo fan-out: advance → execute_step pra cada active → complete_step pra cada → activate_transitions → fan-in correto
- Test coverage target: >=80%

## Success Criteria
- All tests passing
- Test coverage >=80%
- Engine não tem do_advance nem next_active_step
- Engine não chama DateTime.utc_now()
- Engine tem 6 funções públicas: advance, execute_step, complete_step, activate_transitions, check_completion, resume_step
- advance/1 NUNCA executa steps — só ativa em active_steps
