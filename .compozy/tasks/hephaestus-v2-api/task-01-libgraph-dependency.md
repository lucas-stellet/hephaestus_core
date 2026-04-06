# Task 01: Adicionar libgraph como dependencia

## Objetivo

Adicionar `libgraph` ao `mix.exs` como dependencia. Necessario antes de qualquer compile-time validation.

## Arquivos

- `mix.exs` — adicionar `{:libgraph, "~> 0.16"}` em `deps/0`

## Criterio de aceite

- `mix deps.get` executa sem erro
- `Graph.new()` disponivel em IEx
- Testes existentes continuam passando (118 tests)

## Test Skeleton

Nenhum test skeleton — tarefa de configuracao. Validar via `mix deps.get && mix test`.
