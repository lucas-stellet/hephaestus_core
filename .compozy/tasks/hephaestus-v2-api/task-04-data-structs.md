# Task 04: Atualizar Instance e ExecutionEntry

## Objetivo

Adicionar `step_configs` ao Instance. Atualizar types de `atom()` para `module()` e event de `String.t()` para `atom()` em ambos.

## Arquivos

- `lib/hephaestus/core/instance.ex` — adicionar campo `step_configs: %{}`, atualizar types
- `lib/hephaestus/core/execution_entry.ex` — atualizar types

## Depende de

- Nenhuma dependencia (pode rodar em paralelo com Task 02-03)

## Test Skeleton

**Arquivo:** `test/hephaestus/core/instance_v2_test.exs`

```elixir
defmodule Hephaestus.Core.InstanceV2Test do
  use ExUnit.Case, async: true

  alias Hephaestus.Core.Instance

  describe "step_configs field" do
    test "new instance has empty step_configs" do
      # Arrange & Act
      instance = Instance.new(SomeWorkflow, %{})

      # Assert
      assert instance.step_configs == %{}
    end

    test "step_configs can store module => config mapping" do
      # Arrange
      instance = Instance.new(SomeWorkflow, %{})

      # Act
      updated = %{instance | step_configs: Map.put(instance.step_configs, MyStep, %{timeout: 5000})}

      # Assert
      assert updated.step_configs == %{MyStep => %{timeout: 5000}}
    end

    test "step_configs can be cleared per module" do
      # Arrange
      instance = Instance.new(SomeWorkflow, %{})
      with_config = %{instance | step_configs: %{MyStep => %{timeout: 5000}, OtherStep => %{retries: 3}}}

      # Act
      cleared = %{with_config | step_configs: Map.delete(with_config.step_configs, MyStep)}

      # Assert
      assert cleared.step_configs == %{OtherStep => %{retries: 3}}
    end
  end

  describe "types reflect module identity" do
    test "active_steps stores modules" do
      # Arrange
      instance = Instance.new(SomeWorkflow, %{})

      # Act
      updated = %{instance | active_steps: MapSet.new([MyApp.Steps.ValidateOrder])}

      # Assert
      assert MapSet.member?(updated.active_steps, MyApp.Steps.ValidateOrder)
    end

    test "completed_steps stores modules" do
      # Arrange
      instance = Instance.new(SomeWorkflow, %{})

      # Act
      updated = %{instance | completed_steps: MapSet.new([MyApp.Steps.ValidateOrder])}

      # Assert
      assert MapSet.member?(updated.completed_steps, MyApp.Steps.ValidateOrder)
    end

    test "current_step stores module" do
      # Arrange
      instance = Instance.new(SomeWorkflow, %{})

      # Act
      updated = %{instance | current_step: MyApp.Steps.ValidateOrder}

      # Assert
      assert updated.current_step == MyApp.Steps.ValidateOrder
    end
  end
end
```

## Sequencia TDD

1. RED: "new instance has empty step_configs" — falha porque campo nao existe
2. GREEN: adicionar `step_configs: %{}` ao defstruct e @type
3. GREEN: os proximos 2 tests de step_configs passam imediatamente (operacoes de map)
4. GREEN: tests de "types reflect module identity" passam imediatamente (modules sao atoms, type era atom())
5. REFACTOR: atualizar @type para usar `module()` em vez de `atom()` nos typespecs
