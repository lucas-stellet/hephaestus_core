# Task 10: Unit tests — engine funcional com nova API

## Objetivo

Garantir cobertura completa do Engine v2 com testes focados em cada primitiva. Estes testes sao adicionais aos testes migrados da task 09 — cobrem cenarios novos da v2.

## Arquivo

- `test/hephaestus/core/engine_v2_test.exs` (criado na task 07)

## Depende de

- Task 07 (Engine adaptado)
- Task 06 (Workflow macro — test workflows precisam compilar)

## Test Skeletons ja definidos na Task 07

Os test skeletons da task 07 cobrem:
- advance/1 com start module e start com config
- execute_step/2 com config, sem config, e module invalido
- complete_step/4 com snake_case key, limpeza de step_configs, step_key/0 override
- activate_transitions/3 com transit/2, fan-out, fan-in parcial, fan-in completo, config transit
- resume_step/3 com atom event
- check_completion/1

## Tests adicionais nesta task

```elixir
defmodule Hephaestus.Core.EngineV2AdditionalTest do
  use ExUnit.Case, async: true

  alias Hephaestus.Core.{Engine, Instance}

  describe "full linear flow without OTP" do
    test "advances through A -> B -> End entirely in pure functions" do
      # Arrange
      instance = Instance.new(Hephaestus.Test.V2.LinearWorkflow, %{data: "test"})

      # Act — step 1: advance
      {:ok, inst} = Engine.advance(instance)
      assert inst.status == :running
      assert MapSet.member?(inst.active_steps, Hephaestus.Test.V2.StepA)

      # Act — step 2: execute StepA
      {:ok, event} = Engine.execute_step(inst, Hephaestus.Test.V2.StepA)
      assert event == :done

      # Act — step 3: complete StepA
      inst = Engine.complete_step(inst, Hephaestus.Test.V2.StepA, :done, %{})

      # Act — step 4: activate transitions
      inst = Engine.activate_transitions(inst, Hephaestus.Test.V2.StepA, :done)
      assert MapSet.member?(inst.active_steps, Hephaestus.Test.V2.StepB)

      # Act — step 5: execute StepB
      {:ok, event, ctx} = Engine.execute_step(inst, Hephaestus.Test.V2.StepB)
      assert event == :done

      # Act — step 6: complete StepB
      inst = Engine.complete_step(inst, Hephaestus.Test.V2.StepB, :done, ctx)

      # Act — step 7: activate transitions -> End
      inst = Engine.activate_transitions(inst, Hephaestus.Test.V2.StepB, :done)
      assert MapSet.member?(inst.active_steps, Hephaestus.Steps.End)

      # Act — step 8: execute End
      {:ok, event} = Engine.execute_step(inst, Hephaestus.Steps.End)
      assert event == :end

      # Act — step 9: complete End, check completion
      inst = Engine.complete_step(inst, Hephaestus.Steps.End, :end, %{})
      inst = Engine.check_completion(inst)

      # Assert
      assert inst.status == :completed
    end
  end

  describe "full branch flow without OTP" do
    test "takes approved branch" do
      # Arrange
      instance = Instance.new(Hephaestus.Test.V2.BranchWorkflow, %{should_approve: true})

      # Act
      {:ok, inst} = Engine.advance(instance)
      {:ok, event} = Engine.execute_step(inst, Hephaestus.Test.V2.BranchStep)

      # Assert
      assert event == :approved

      # Act — activate and follow approved branch
      inst = Engine.complete_step(inst, Hephaestus.Test.V2.BranchStep, :approved, %{})
      inst = Engine.activate_transitions(inst, Hephaestus.Test.V2.BranchStep, :approved)

      # Assert
      assert MapSet.member?(inst.active_steps, Hephaestus.Test.V2.ApproveStep)
      refute MapSet.member?(inst.active_steps, Hephaestus.Test.V2.RejectStep)
    end
  end

  describe "dynamic transit/3 flow" do
    test "resolves transit/3 using context" do
      # Arrange
      instance = Instance.new(Hephaestus.Test.V2.DynamicWorkflow, %{use_b: true})

      {:ok, inst} = Engine.advance(instance)
      {:ok, :done} = Engine.execute_step(inst, Hephaestus.Test.V2.StepA)
      inst = Engine.complete_step(inst, Hephaestus.Test.V2.StepA, :done, %{})

      # Act
      inst = Engine.activate_transitions(inst, Hephaestus.Test.V2.StepA, :done)

      # Assert — transit/3 should route to StepB because ctx.initial.use_b is true
      assert MapSet.member?(inst.active_steps, Hephaestus.Test.V2.StepB)
      refute MapSet.member?(inst.active_steps, Hephaestus.Test.V2.StepC)
    end
  end
end
```

## Sequencia TDD

Estes testes validam fluxos completos — devem todos passar apos tasks 06-07 estarem implementadas. Se algum falha, indica bug na implementacao do engine ou macro.
