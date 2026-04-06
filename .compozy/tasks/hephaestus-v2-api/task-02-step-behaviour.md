# Task 02: Atualizar Step behaviour com events/0 e step_key/0

## Objetivo

Adicionar `events/0` (obrigatorio) e `step_key/0` (opcional) ao behaviour `Hephaestus.Steps.Step`. Mudar event type de `String.t()` para `atom()`.

## Arquivos

- `lib/hephaestus/steps/step.ex` — adicionar callbacks, atualizar types

## Mudancas

```elixir
# Antes
@type event :: String.t()
@callback execute(Instance.t(), config(), Context.t()) :: result()

# Depois
@type event :: atom()
@callback events() :: [atom()]
@callback step_key() :: atom()
@callback execute(Instance.t(), config(), Context.t()) :: result()
@optional_callbacks [step_key: 0]
```

## Test Skeleton

**Arquivo:** `test/hephaestus/steps/step_behaviour_test.exs`

```elixir
defmodule Hephaestus.Steps.StepBehaviourTest do
  use ExUnit.Case, async: true

  describe "behaviour callbacks" do
    test "module implementing events/0 and execute/3 satisfies behaviour" do
      # Arrange
      defmodule FullStep do
        @behaviour Hephaestus.Steps.Step

        @impl true
        def events, do: [:done, :failed]

        @impl true
        def execute(_instance, _config, _context), do: {:ok, :done}
      end

      # Act
      events = FullStep.events()
      result = FullStep.execute(nil, nil, nil)

      # Assert
      assert events == [:done, :failed]
      assert {:ok, :done} = result
    end

    test "module implementing optional step_key/0 returns custom key" do
      # Arrange
      defmodule StepWithKey do
        @behaviour Hephaestus.Steps.Step

        @impl true
        def events, do: [:done]

        @impl true
        def step_key, do: :custom_key

        @impl true
        def execute(_instance, _config, _context), do: {:ok, :done}
      end

      # Act
      key = StepWithKey.step_key()

      # Assert
      assert key == :custom_key
    end

    test "module without step_key/0 does not export it" do
      # Arrange
      defmodule StepWithoutKey do
        @behaviour Hephaestus.Steps.Step

        @impl true
        def events, do: [:done]

        @impl true
        def execute(_instance, _config, _context), do: {:ok, :done}
      end

      # Act & Assert
      refute function_exported?(StepWithoutKey, :step_key, 0)
    end
  end
end
```

## Sequencia TDD

1. RED: test "module implementing events/0 and execute/3 satisfies behaviour" — falha porque `events/0` nao existe no behaviour
2. GREEN: adicionar `@callback events() :: [atom()]` ao behaviour
3. RED: test "module implementing optional step_key/0 returns custom key" — falha porque `step_key/0` nao existe no behaviour
4. GREEN: adicionar `@callback step_key() :: atom()` e `@optional_callbacks [step_key: 0]`
5. RED: test "module without step_key/0 does not export it" — deve passar imediatamente (confirma optional)
6. REFACTOR: atualizar types de event de `String.t()` para `atom()`
