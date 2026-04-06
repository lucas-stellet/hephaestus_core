# Task 05: Remover Step struct e StepDefinition protocol

## Objetivo

Remover `%Hephaestus.Core.Step{}` struct e `Hephaestus.StepDefinition` protocol. A partir daqui o projeto NAO compila ate tasks 06-07 estarem completas.

## Arquivos

- `lib/hephaestus/core/step.ex` — DELETAR
- `lib/hephaestus/core/step_definition.ex` — DELETAR

## Depende de

- Task 04 (Instance atualizado)

## IMPORTANTE

Esta task DEVE ser feita junto com tasks 06 e 07 num unico commit, pois o projeto nao compila entre elas. A separacao em tasks e para clareza de escopo, nao para commits independentes.

## Test Skeleton

Nenhum test skeleton proprio. A validacao e que os testes das tasks 06, 07, 09, e 10 passam sem esses arquivos.

## Acoes

1. Deletar `lib/hephaestus/core/step.ex`
2. Deletar `lib/hephaestus/core/step_definition.ex`
3. Remover qualquer `alias Hephaestus.StepDefinition` ou `alias Hephaestus.Core.Step` no engine.ex
4. Remover `import` ou `require` desses modulos em qualquer lugar
