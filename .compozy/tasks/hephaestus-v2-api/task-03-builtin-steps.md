# Task 03: Adicionar events/0 aos built-in steps

## Objetivo

Adicionar `events/0` a cada built-in step e mudar returns de string para atom.

## Arquivos

- `lib/hephaestus/steps/end_step.ex` — events/0 retorna `[:end]`, execute retorna `{:ok, :end}`
- `lib/hephaestus/steps/debug.ex` — events/0 retorna `[:completed]`, execute retorna `{:ok, :completed}`
- `lib/hephaestus/steps/wait.ex` — events/0 retorna `[:timeout]`, execute continua `{:async}`
- `lib/hephaestus/steps/wait_for_event.ex` — events/0 retorna `[:received]`, execute continua `{:async}`

## Depende de

- Task 02 (Step behaviour com events/0)

## Test Skeleton

**Arquivo:** `test/hephaestus/steps/builtin_steps_v2_test.exs`

```elixir
defmodule Hephaestus.Steps.BuiltinStepsV2Test do
  use ExUnit.Case, async: true

  alias Hephaestus.Core.{Context, Instance}
  alias Hephaestus.Steps.{End, Debug, Wait, WaitForEvent}

  defp dummy_instance do
    %Instance{
      id: "test-123",
      workflow: __MODULE__,
      context: Context.new(%{}),
      active_steps: MapSet.new(),
      completed_steps: MapSet.new(),
      execution_history: []
    }
  end

  describe "End" do
    test "events/0 returns [:end]" do
      # Act
      events = End.events()

      # Assert
      assert events == [:end]
    end

    test "execute/3 returns {:ok, :end}" do
      # Arrange
      instance = dummy_instance()

      # Act
      result = End.execute(instance, nil, instance.context)

      # Assert
      assert {:ok, :end} = result
    end
  end

  describe "Debug" do
    test "events/0 returns [:completed]" do
      # Act
      events = Debug.events()

      # Assert
      assert events == [:completed]
    end

    test "execute/3 returns {:ok, :completed}" do
      # Arrange
      instance = dummy_instance()

      # Act
      result = Debug.execute(instance, nil, instance.context)

      # Assert
      assert {:ok, :completed} = result
    end
  end

  describe "Wait" do
    test "events/0 returns [:timeout]" do
      # Act
      events = Wait.events()

      # Assert
      assert events == [:timeout]
    end

    test "execute/3 returns {:async}" do
      # Arrange
      instance = dummy_instance()

      # Act
      result = Wait.execute(instance, nil, instance.context)

      # Assert
      assert {:async} = result
    end
  end

  describe "WaitForEvent" do
    test "events/0 returns [:received]" do
      # Act
      events = WaitForEvent.events()

      # Assert
      assert events == [:received]
    end

    test "execute/3 returns {:async}" do
      # Arrange
      instance = dummy_instance()

      # Act
      result = WaitForEvent.execute(instance, nil, instance.context)

      # Assert
      assert {:async} = result
    end
  end
end
```

## Sequencia TDD

1. RED: End.events/0 — falha porque nao implementa events/0
2. GREEN: adicionar `def events, do: [:end]` ao End
3. RED: End.execute retorna {:ok, :end} — falha porque retorna {:ok, "completed"}
4. GREEN: mudar return para {:ok, :end}
5. Repetir para Debug, Wait, WaitForEvent (cada um tem 2 tests)
6. REFACTOR: verificar que nenhum test existente quebrou (os testes v1 que usam strings vao quebrar — isso e esperado e sera resolvido nas tasks seguintes)
