---
status: pending
domain: Core
type: Feature Implementation
scope: Full
complexity: high
dependencies:
  - task_01
  - task_02
  - task_03
---

# Task 04: Engine funcional (advance, execute_step, complete_step, resume)

## Overview

Implementar o engine funcional puro — o coração do Hephaestus. Funções que transformam dados sem side-effects: executar steps, resolver transições, gerenciar fan-out/fan-in, e propagar context. Deve ser testável em IEx sem nenhum processo OTP.

<critical>
- ALWAYS READ the PRD and TechSpec before starting
- REFERENCE TECHSPEC for implementation details — do not duplicate here
- FOCUS ON "WHAT" — describe what needs to be accomplished, not how
- MINIMIZE CODE — show code only to illustrate current structure or problem areas
- TESTS REQUIRED — every task MUST include tests in deliverables
</critical>

<requirements>
- `advance/1` DEVE executar steps ativos sequencialmente até pausar, completar ou falhar
- `advance/1` DEVE ativar initial_step se instância está :pending
- `execute_step/2` DEVE despachar via protocolo StepDefinition e chamar module.execute/3
- `complete_step/4` DEVE marcar step como completado, adicionar ao completed_steps, e fazer Context.put_step_result/3
- `complete_step` DEVE adicionar ExecutionEntry ao execution_history
- `resume/2` DEVE retomar instância pausada em :waiting
- Fan-out: transição para lista de atoms DEVE ativar todos os targets em active_steps
- Fan-in: step DEVE só ser ativado quando TODOS predecessores estão em completed_steps (MapSet.subset?)
- Status DEVE mudar: :pending → :running → :waiting | :completed | :failed
- Engine NÃO DEVE ter side-effects (sem Logger, sem processos, sem IO)
</requirements>

## Subtasks
- [ ] 4.1 Implementar `advance/1` — loop de execução
- [ ] 4.2 Implementar `execute_step/2` — dispatch via protocolo
- [ ] 4.3 Implementar `complete_step/4` — marca step, merge context, history
- [ ] 4.4 Implementar resolução de transições (atom e lista para fan-out)
- [ ] 4.5 Implementar lógica de fan-in com `MapSet.subset?`
- [ ] 4.6 Implementar `resume/2` — retoma instância pausada
- [ ] 4.7 Implementar transição de status (:pending → :running → etc.)

## Implementation Details

### Relevant Files
- `lib/hephaestus/core/engine.ex` — todas as funções do engine

### Dependent Files
- `lib/hephaestus/core/instance.ex` — Instance struct manipulada pelo engine
- `lib/hephaestus/core/context.ex` — Context.put_step_result usado pelo engine
- `lib/hephaestus/core/step_definition.ex` — Protocolo para dispatch
- `lib/hephaestus/core/workflow.ex` — __step__, __predecessors__ usados pelo engine
- `lib/hephaestus/steps/` — Built-in steps chamados pelo engine

### Related ADRs
- [ADR-001: Arquitetura do Hephaestus Core](../adrs/adr-001.md) — Engine como core funcional puro
- [ADR-004: Context como struct com namespace](../adrs/adr-004.md) — Context.put_step_result no complete_step

## Deliverables
- Engine funcional completo sem side-effects
- Suporte a workflows lineares, com branch, fan-out e fan-in
- Unit tests com 80%+ coverage **(REQUIRED)**

## Tests

### Test support: `test/support/test_steps.ex`

```elixir
defmodule Hephaestus.Test.PassStep do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def execute(_instance, _config, _context), do: {:ok, "done"}
end

defmodule Hephaestus.Test.PassWithContextStep do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def execute(_instance, _config, _context), do: {:ok, "done", %{processed: true}}
end

defmodule Hephaestus.Test.BranchStep do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def execute(_instance, _config, context) do
    if context.initial[:should_approve] do
      {:ok, "approved"}
    else
      {:ok, "rejected"}
    end
  end
end

defmodule Hephaestus.Test.AsyncStep do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def execute(_instance, _config, _context), do: {:async}
end

defmodule Hephaestus.Test.FailStep do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def execute(_instance, _config, _context), do: {:error, :something_went_wrong}
end
```

### Test support: `test/support/test_workflows.ex`

```elixir
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

defmodule Hephaestus.Test.BranchWorkflow do
  use Hephaestus.Workflow
  alias Hephaestus.Core.Step

  @impl true
  def definition do
    %Hephaestus.Core.Workflow{
      initial_step: :check,
      steps: [
        %Step{ref: :check, module: Hephaestus.Test.BranchStep, transitions: %{"approved" => :approve, "rejected" => :reject}},
        %Step{ref: :approve, module: Hephaestus.Test.PassStep, transitions: %{"done" => :finish}},
        %Step{ref: :reject, module: Hephaestus.Test.PassStep, transitions: %{"done" => :finish}},
        %Step{ref: :finish, module: Hephaestus.Steps.End}
      ]
    }
  end
end

defmodule Hephaestus.Test.ParallelWorkflow do
  use Hephaestus.Workflow
  alias Hephaestus.Core.Step

  @impl true
  def definition do
    %Hephaestus.Core.Workflow{
      initial_step: :start,
      steps: [
        %Step{ref: :start, module: Hephaestus.Test.PassStep, transitions: %{"done" => [:branch_a, :branch_b]}},
        %Step{ref: :branch_a, module: Hephaestus.Test.PassWithContextStep, transitions: %{"done" => :join}},
        %Step{ref: :branch_b, module: Hephaestus.Test.PassWithContextStep, transitions: %{"done" => :join}},
        %Step{ref: :join, module: Hephaestus.Test.PassStep, transitions: %{"done" => :finish}},
        %Step{ref: :finish, module: Hephaestus.Steps.End}
      ]
    }
  end
end

defmodule Hephaestus.Test.AsyncWorkflow do
  use Hephaestus.Workflow
  alias Hephaestus.Core.Step

  @impl true
  def definition do
    %Hephaestus.Core.Workflow{
      initial_step: :step_a,
      steps: [
        %Step{ref: :step_a, module: Hephaestus.Test.PassStep, transitions: %{"done" => :wait}},
        %Step{ref: :wait, module: Hephaestus.Test.AsyncStep, transitions: %{"timeout" => :step_b}},
        %Step{ref: :step_b, module: Hephaestus.Test.PassStep, transitions: %{"done" => :finish}},
        %Step{ref: :finish, module: Hephaestus.Steps.End}
      ]
    }
  end
end
```

### Test file: `test/hephaestus/core/engine_test.exs`

```elixir
defmodule Hephaestus.Core.EngineTest do
  use ExUnit.Case, async: true

  alias Hephaestus.Core.{Engine, Instance, Context}

  describe "advance/1 — linear workflow" do
    test "executes all steps and completes" do
      # Arrange
      instance = Instance.new(Hephaestus.Test.LinearWorkflow, %{})

      # Act
      {:ok, instance} = Engine.advance(instance)

      # Assert
      assert instance.status == :completed
      assert MapSet.member?(instance.completed_steps, :step_a)
      assert MapSet.member?(instance.completed_steps, :step_b)
      assert MapSet.member?(instance.completed_steps, :finish)
    end

    test "accumulates context from steps" do
      # Arrange
      instance = Instance.new(Hephaestus.Test.LinearWorkflow, %{})

      # Act
      {:ok, instance} = Engine.advance(instance)

      # Assert
      assert %{processed: true} = instance.context.steps[:step_b]
    end

    test "preserves initial context" do
      # Arrange
      instance = Instance.new(Hephaestus.Test.LinearWorkflow, %{order_id: 123})

      # Act
      {:ok, instance} = Engine.advance(instance)

      # Assert
      assert instance.context.initial == %{order_id: 123}
    end

    test "builds execution history" do
      # Arrange
      instance = Instance.new(Hephaestus.Test.LinearWorkflow, %{})

      # Act
      {:ok, instance} = Engine.advance(instance)

      # Assert
      refs = Enum.map(instance.execution_history, & &1.step_ref)
      assert :step_a in refs
      assert :step_b in refs
      assert :finish in refs
    end
  end

  describe "advance/1 — branching workflow" do
    test "follows true branch" do
      # Arrange
      instance = Instance.new(Hephaestus.Test.BranchWorkflow, %{should_approve: true})

      # Act
      {:ok, instance} = Engine.advance(instance)

      # Assert
      assert instance.status == :completed
      assert MapSet.member?(instance.completed_steps, :approve)
      refute MapSet.member?(instance.completed_steps, :reject)
    end

    test "follows false branch" do
      # Arrange
      instance = Instance.new(Hephaestus.Test.BranchWorkflow, %{should_approve: false})

      # Act
      {:ok, instance} = Engine.advance(instance)

      # Assert
      assert instance.status == :completed
      assert MapSet.member?(instance.completed_steps, :reject)
      refute MapSet.member?(instance.completed_steps, :approve)
    end
  end

  describe "advance/1 — fan-out / fan-in" do
    test "activates all fan-out targets" do
      # Arrange
      instance = Instance.new(Hephaestus.Test.ParallelWorkflow, %{})

      # Act
      {:ok, instance} = Engine.advance(instance)

      # Assert
      assert instance.status == :completed
      assert MapSet.member?(instance.completed_steps, :branch_a)
      assert MapSet.member?(instance.completed_steps, :branch_b)
      assert MapSet.member?(instance.completed_steps, :join)
    end

    test "fan-in step receives context from all predecessors" do
      # Arrange
      instance = Instance.new(Hephaestus.Test.ParallelWorkflow, %{})

      # Act
      {:ok, instance} = Engine.advance(instance)

      # Assert
      assert %{processed: true} = instance.context.steps[:branch_a]
      assert %{processed: true} = instance.context.steps[:branch_b]
    end

    test "join step only executes after all predecessors complete" do
      # Arrange
      instance = Instance.new(Hephaestus.Test.ParallelWorkflow, %{})

      # Act
      {:ok, instance} = Engine.advance(instance)

      # Assert — join comes after both branches in history
      history_refs = Enum.map(instance.execution_history, & &1.step_ref)
      join_idx = Enum.find_index(history_refs, &(&1 == :join))
      branch_a_idx = Enum.find_index(history_refs, &(&1 == :branch_a))
      branch_b_idx = Enum.find_index(history_refs, &(&1 == :branch_b))
      assert join_idx > branch_a_idx
      assert join_idx > branch_b_idx
    end
  end

  describe "advance/1 — async step" do
    test "pauses at async step with waiting status" do
      # Arrange
      instance = Instance.new(Hephaestus.Test.AsyncWorkflow, %{})

      # Act
      {:ok, instance} = Engine.advance(instance)

      # Assert
      assert instance.status == :waiting
      assert MapSet.member?(instance.active_steps, :wait)
      assert MapSet.member?(instance.completed_steps, :step_a)
    end
  end

  describe "advance/1 — error handling" do
    test "returns error when step fails" do
      # Arrange
      defmodule FailWorkflow do
        use Hephaestus.Workflow
        alias Hephaestus.Core.Step

        @impl true
        def definition do
          %Hephaestus.Core.Workflow{
            initial_step: :start,
            steps: [
              %Step{ref: :start, module: Hephaestus.Test.FailStep, transitions: %{"done" => :finish}},
              %Step{ref: :finish, module: Hephaestus.Steps.End}
            ]
          }
        end
      end

      instance = Instance.new(FailWorkflow, %{})

      # Act
      result = Engine.advance(instance)

      # Assert
      assert {:error, :something_went_wrong} = result
    end
  end

  describe "resume/2" do
    test "resumes waiting instance and continues execution" do
      # Arrange
      instance = Instance.new(Hephaestus.Test.AsyncWorkflow, %{})
      {:ok, paused} = Engine.advance(instance)
      assert paused.status == :waiting

      # Act
      resumed = Engine.resume(paused, "timeout")
      {:ok, completed} = Engine.advance(resumed)

      # Assert
      assert completed.status == :completed
      assert MapSet.member?(completed.completed_steps, :step_b)
    end
  end

  describe "complete_step/4" do
    test "marks step as completed and updates context" do
      # Arrange
      instance = Instance.new(Hephaestus.Test.LinearWorkflow, %{})
      instance = %{instance | active_steps: MapSet.new([:step_a]), status: :running}

      # Act
      instance = Engine.complete_step(instance, :step_a, "done", %{result: "ok"})

      # Assert
      assert MapSet.member?(instance.completed_steps, :step_a)
      refute MapSet.member?(instance.active_steps, :step_a)
      assert %{result: "ok"} = instance.context.steps[:step_a]
    end

    test "adds execution entry to history" do
      # Arrange
      instance = Instance.new(Hephaestus.Test.LinearWorkflow, %{})
      instance = %{instance | active_steps: MapSet.new([:step_a]), status: :running}

      # Act
      instance = Engine.complete_step(instance, :step_a, "done", %{})

      # Assert
      assert [%{step_ref: :step_a, event: "done"} | _] = instance.execution_history
    end
  end

  describe "status transitions" do
    test "pending → running on first advance" do
      # Arrange
      instance = Instance.new(Hephaestus.Test.AsyncWorkflow, %{})
      assert instance.status == :pending

      # Act
      {:ok, instance} = Engine.advance(instance)

      # Assert — paused at async, but was running before
      assert instance.status == :waiting
      assert MapSet.member?(instance.completed_steps, :step_a)
    end
  end
end
```

- Unit tests:
  - [x] Linear: executes all steps and completes
  - [x] Linear: accumulates context from steps
  - [x] Linear: preserves initial context
  - [x] Linear: builds execution history
  - [x] Branch: follows true branch
  - [x] Branch: follows false branch
  - [x] Fan-out/fan-in: activates all targets
  - [x] Fan-out/fan-in: join receives context from predecessors
  - [x] Fan-out/fan-in: join waits for all predecessors
  - [x] Async: pauses at async step with waiting status
  - [x] Error: returns error when step fails
  - [x] Resume: resumes and continues execution
  - [x] complete_step: marks completed and updates context
  - [x] complete_step: adds execution entry
  - [x] Status transitions: pending → running → waiting/completed
- Test coverage target: >=80%

## Success Criteria
- All tests passing
- Test coverage >=80%
- Engine funciona em IEx sem nenhum processo OTP
- Fan-out e fan-in funcionam corretamente
- Context namespaced por step ref
