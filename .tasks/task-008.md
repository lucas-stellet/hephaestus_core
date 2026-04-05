# Task 008: Connector behaviour

**Wave**: 0 | **Effort**: S
**Depends on**: none
**Blocks**: none

## Objective

Definir o behaviour simples de Connector — contrato para integrações com serviços externos. A lib não traz implementações concretas. O behaviour padroniza o contrato pra libs futuras construírem em cima.

## Files

**Create:** `lib/hephaestus/connectors/connector.ex` — behaviour definition
**Create:** `test/hephaestus/connectors/connector_test.exs`

## Requirements

- Behaviour callbacks: `execute/3` (action atom, params map, config map → `{:ok, map()} | {:error, term()}`), `supported_actions/0` (→ `[atom()]`)
- Teste usa mock connector implementando o behaviour pra validar contrato
- Módulo que implementa sem todos callbacks deve gerar warning do compilador
- TDD: ver skeletons em .compozy/tasks/hephaestus-core/task_08.md

## Done when

- [ ] Behaviour definido com @callback e @type specs
- [ ] Mock connector passa nos testes
- [ ] Todos os testes passando
- [ ] Coverage >=80%
