# Task 012: Crash recovery do Runner.Local

**Wave**: 7 | **Effort**: M
**Depends on**: task-010, task-011
**Blocks**: none

## Objective

Quando o GenServer de uma instância morre (crash, kill, exceção), o DynamicSupervisor pode reiniciá-lo. No estado atual, o child_spec usa `restart: :temporary` (runner/local.ex, start_instance/3 linha 51) — o que significa que o supervisor NÃO reinicia após crash. Além disso, o init/1 (linha 82) recebe o state com a instância original, não recupera do Storage.

O objetivo é: (1) mudar a estratégia de restart, (2) fazer o init recuperar o estado do Storage quando a instância já existe, e (3) testar que após crash a instância continua funcional.

<critical>
- ALWAYS READ the PRD and TechSpec before starting
- REFERENCE TECHSPEC for implementation details — do not duplicate here
- FOCUS ON "WHAT" — describe what needs to be accomplished, not how
- TESTS REQUIRED — every task MUST include tests in deliverables
</critical>

<requirements>
**Child spec — runner/local.ex start_instance/3 linhas 48-52:**
- Mudar `restart: :temporary` para `restart: :transient` — reinicia apenas em caso de crash anormal (não quando para com :normal ou :shutdown)
- Isso permite que instâncias completadas parem sem reiniciar, mas instâncias que crasham sejam reiniciadas

**start_link/1 — runner/local.ex linhas 22-34:**
- DEVE continuar recebendo opts com instance, registry, storage, task_supervisor
- Após crash, o DynamicSupervisor chama start_link de novo com os mesmos opts — a instância no opts pode estar desatualizada
- Adicionar o instance_id aos opts para que o init possa recuperar do Storage

**init/1 — runner/local.ex linhas 82-85:**
- DEVE tentar recuperar a instância do Storage antes de usar a do opts
- Se Storage tem uma instância mais recente (mesmo id, status diferente de :pending) → usar a do Storage
- Se Storage não tem a instância ou falha → usar a do opts (caso de primeira inicialização)
- Após recuperar, chamar {:continue, :advance} para retomar de onde parou
- Instância em :waiting → GenServer fica alive esperando resume (handle_continue(:advance) já trata isso)
- Instância em :running com active_steps → retomar execução via {:continue, :execute_active}
- Instância :completed ou :failed → parar imediatamente (não deveria acontecer com :transient, mas ser defensivo)

**Timers perdidos:**
- Schedule_resume usa Process.send_after que morre com o processo
- Após crash recovery, timers de wait steps SÃO perdidos — isso é limitação conhecida do Runner.Local
- DOCUMENTAR com @moduledoc que timers não sobrevivem crash (será resolvido com Runner.Oban)
- NÃO tentar reimplementar timers no recovery — complexidade desnecessária pro MVP

**Lookup após restart:**
- O remember_registry/1 (linha 240) usa :persistent_term — sobrevive ao crash do processo
- lookup_instance/1 (linhas 226-234) deve continuar funcionando após restart porque :persistent_term persiste
- O via_tuple na registration (linha 33) registra o novo PID no Registry automaticamente
</requirements>

<constraints>
- NÃO modificar Engine — é puro, não tem nada a ver com crash recovery
- NÃO modificar Storage — o GenServer já persiste após cada mudança, recovery é só ler de volta
- NÃO tentar recuperar timers — documentar como limitação
- NÃO mudar o behaviour Runner — a interface pública não muda
- NÃO modificar testes existentes — apenas adicionar novos
</constraints>

## Subtasks
- [ ] 12.1 Mudar restart: :temporary para restart: :transient no child_spec (linha 51)
- [ ] 12.2 Refatorar init/1 para recuperar instância do Storage se disponível
- [ ] 12.3 Adicionar @moduledoc nota sobre timers não sobreviverem crash
- [ ] 12.4 Adicionar testes de crash recovery

## Implementation Details

### Relevant Files
- `lib/hephaestus/runtime/runner/local.ex` — linhas 48-52 (child_spec), 82-85 (init), 22-34 (start_link)

### Dependent Files
- `lib/hephaestus/runtime/storage/ets.ex` — usado para recuperar instância no init (chamada existente, sem modificação)
- `test/hephaestus/runtime/runner/local_test.exs` — adicionar describe "crash recovery"

### Related ADRs
- [ADR-003: Runner como adapter](../adrs/adr-003.md) — Runner.Local é MVP, limitações (como timers perdidos) serão resolvidas com Runner.Oban

### Boundary Contract
- **Este task modifica:** Runner.Local init e child_spec — comportamento de restart
- **NÃO modifica:** Engine, Storage, Runner behaviour, testes existentes
- **Limitação documentada:** timers de wait steps não sobrevivem crash

## Deliverables
- Runner.Local com restart: :transient e init que recupera do Storage
- @moduledoc documentando limitação de timers
- Testes de crash recovery passando
- mix test completo com 0 falhas
- Test coverage >=80% **(REQUIRED)**

## Tests

Adicionar novo describe "crash recovery" em test/hephaestus/runtime/runner/local_test.exs:

- Integration tests:
  - [ ] Instância waiting sobrevive crash: start AsyncWorkflow → waiting → matar GenServer (Process.exit(pid, :kill)) → sleep para supervisor reiniciar → verificar que processo novo existe no Registry → resume(id, "timeout") → completed
  - [ ] Instância waiting mantém estado após crash: start AsyncWorkflow → waiting → verificar completed_steps no Storage → matar GenServer → sleep → verificar que Storage ainda tem os mesmos completed_steps → resume funciona
  - [ ] Instância completed NÃO é reiniciada: start LinearWorkflow → completed → GenServer já parou → verificar que Registry não tem o PID (restart: :transient não reinicia em :normal stop)

- Test coverage target: >=80%

## Success Criteria
- mix test: 0 falhas
- Instância em :waiting sobrevive crash e aceita resume
- Instância :completed não é reiniciada
- @moduledoc documenta limitação de timers
- restart: :transient no child_spec
