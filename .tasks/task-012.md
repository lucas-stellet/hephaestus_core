# Task 012: Crash recovery do Runner.Local e testes de resiliência

**Wave**: 2 | **Effort**: M
**Depends on**: task-010, task-011
**Blocks**: none

## Objective

Garantir que quando o GenServer de uma instância morre, o DynamicSupervisor reinicia e o estado é recuperado do Storage (ETS). Adicionar testes que simulam crash e verificam retomada.

## Files

**Modify:** `lib/hephaestus/runtime/runner/local.ex` — init deve recuperar estado do Storage se instância já existe
**Modify:** `test/hephaestus/runtime/runner/local_test.exs` — testes de crash recovery

## Requirements

- No init do GenServer, se a instância já existe no Storage (put anterior), recuperar o estado dela
- Após crash + restart pelo supervisor, a instância deve continuar de onde parou
- Instância em :waiting deve continuar esperando após recovery
- Instância em :running deve retomar execução após recovery
- Timers de schedule_resume são perdidos no crash — documentar esse comportamento (será resolvido com Runner.Oban)

## Done when

- [ ] GenServer.init recupera estado do Storage se disponível
- [ ] Teste: mata o GenServer, supervisor reinicia, instância retoma
- [ ] Teste: instância waiting após crash ainda aceita resume
- [ ] Teste: instância running após crash retoma advance
- [ ] Todos os testes passando
- [ ] Coverage >=80%
