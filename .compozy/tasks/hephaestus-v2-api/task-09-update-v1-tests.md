# Task 09: Atualizar test support e testes v1

## Objetivo

Migrar `test/support/test_steps.ex` e `test/support/test_workflows.ex` pra nova API. Atualizar TODOS os testes existentes que usam a API v1 (strings como eventos, atom refs, %Step{}, definition/0).

## Arquivos

- `test/support/test_steps.ex` — adicionar `events/0` a cada step, mudar returns pra atom
- `test/support/test_workflows.ex` — reescrever workflows com `start/0` + `transit/2` em vez de `definition/0`
- `test/hephaestus/core/engine_test.exs` — atualizar pra nova API (modules em vez de refs, atoms em vez de strings)
- `test/hephaestus/core/workflow_test.exs` — atualizar pra nova validacao
- `test/hephaestus/core/instance_test.exs` — ajustar se necessario
- `test/hephaestus/core/context_test.exs` — ajustar se necessario
- `test/hephaestus/steps/*_test.exs` — ajustar returns pra atoms
- `test/hephaestus/runtime/runner/local_test.exs` — ajustar events pra atoms
- `test/hephaestus_test.exs` — ajustar events pra atoms
- `test/hephaestus/entry_module_test.exs` — ajustar events pra atoms

## Depende de

- Tasks 02-08 (toda a implementacao v2)

## Mudancas em test_steps.ex

```elixir
# Antes
defmodule Hephaestus.Test.PassStep do
  @behaviour Hephaestus.Steps.Step
  def execute(_instance, _config, _context), do: {:ok, "done"}
end

# Depois
defmodule Hephaestus.Test.PassStep do
  @behaviour Hephaestus.Steps.Step
  @impl true
  def events, do: [:done]
  @impl true
  def execute(_instance, _config, _context), do: {:ok, :done}
end
```

## Mudancas em test_workflows.ex

```elixir
# Antes
defmodule Hephaestus.Test.LinearWorkflow do
  use Hephaestus.Workflow
  alias Hephaestus.Core.Step
  @impl true
  def definition do
    %Hephaestus.Core.Workflow{
      initial_step: :step_a,
      steps: [
        %Step{ref: :step_a, module: Hephaestus.Test.PassStep, transitions: %{"done" => :step_b}},
        %Step{ref: :step_b, module: Hephaestus.Test.PassWithContextStep, transitions: %{"done" => :finish}},
        %Step{ref: :finish, module: Hephaestus.Steps.End}
      ]
    }
  end
end

# Depois
defmodule Hephaestus.Test.LinearWorkflow do
  use Hephaestus.Workflow
  @impl true
  def start, do: Hephaestus.Test.PassStep
  @impl true
  def transit(Hephaestus.Test.PassStep, :done), do: Hephaestus.Test.PassWithContextStep
  def transit(Hephaestus.Test.PassWithContextStep, :done), do: Hephaestus.Steps.End
end
```

## IMPORTANTE

Cada step module agora so pode aparecer UMA VEZ por workflow. Se dois workflows usam o mesmo step em posicoes diferentes, isso funciona entre workflows, mas NAO dentro do mesmo workflow. Ajustar os test workflows se necessario criando step aliases via defdelegate ou modules distintos.

## Criterio de aceite

- `mix test` — TODOS os 118+ testes passando
- Zero warnings de compilacao
- Nenhuma referencia a `%Step{}`, `StepDefinition`, `definition/0`, ou eventos string em test files

## Sequencia TDD

Nao e TDD classico — e migracao de testes existentes. A sequencia e:

1. Migrar `test_steps.ex` — adicionar events/0 e mudar returns
2. Migrar `test_workflows.ex` — reescrever com start/0 + transit/2
3. Migrar testes de core (engine, workflow, instance, context)
4. Migrar testes de steps (end, debug, wait, wait_for_event)
5. Migrar testes de runtime (runner/local, storage)
6. Migrar testes de integracao (hephaestus_test, entry_module_test)
7. Rodar `mix test` e resolver qualquer falha restante
