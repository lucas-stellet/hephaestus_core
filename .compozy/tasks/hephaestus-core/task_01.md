---
status: pending
domain: Core
type: Feature Implementation
scope: Full
complexity: medium
dependencies: []
---

# Task 01: Project scaffolding + Core data structs + StepDefinition protocol

## Overview

Criar a estrutura de diretórios da lib e implementar todas as structs do core funcional (Context, Instance, Workflow, Step, ExecutionEntry) junto com o protocolo StepDefinition. Esta é a fundação sobre a qual todo o resto é construído — nenhum processo OTP, nenhum side-effect, apenas dados e contratos.

<critical>
- ALWAYS READ the PRD and TechSpec before starting
- REFERENCE TECHSPEC for implementation details — do not duplicate here
- FOCUS ON "WHAT" — describe what needs to be accomplished, not how
- MINIMIZE CODE — show code only to illustrate current structure or problem areas
- TESTS REQUIRED — every task MUST include tests in deliverables
</critical>

<requirements>
- Todas as structs DEVEM usar `@enforce_keys` para campos obrigatórios
- `Context` DEVE ter campos `initial` e `steps` com funções `new/1` e `put_step_result/3`
- `Instance` DEVE ter campos: id, workflow, status, context, active_steps (MapSet), completed_steps (MapSet), execution_history
- `Step` DEVE ter campos: ref, module, config, transitions
- `Workflow` DEVE ter campos: initial_step, steps
- `ExecutionEntry` DEVE ter campos: step_ref, event, timestamp, context_updates
- Protocolo `StepDefinition` DEVE definir: ref/1, module/1, config/1, transitions/1
- `Core.Step` DEVE implementar o protocolo `StepDefinition`
- Estrutura de diretórios conforme TechSpec (core/, runtime/, steps/, connectors/)
</requirements>

## Subtasks
- [ ] 1.1 Criar estrutura de diretórios (lib/hephaestus/core/, runtime/, steps/, connectors/)
- [ ] 1.2 Implementar struct `Context` com `new/1` e `put_step_result/3`
- [ ] 1.3 Implementar struct `Instance` com `new/2` e status types
- [ ] 1.4 Implementar struct `Workflow`
- [ ] 1.5 Implementar struct `Step` com `@enforce_keys`
- [ ] 1.6 Implementar struct `ExecutionEntry`
- [ ] 1.7 Definir protocolo `StepDefinition` e implementação para `Core.Step`

## Implementation Details

### Relevant Files
- `lib/hephaestus/core/context.ex` — struct do context
- `lib/hephaestus/core/instance.ex` — struct da instância
- `lib/hephaestus/core/workflow.ex` — struct do workflow
- `lib/hephaestus/core/step.ex` — struct genérica + implementação do protocolo
- `lib/hephaestus/core/execution_entry.ex` — struct do histórico
- `lib/hephaestus/core/step_definition.ex` — protocolo StepDefinition

### Related ADRs
- [ADR-002: Protocolo StepDefinition](../adrs/adr-002.md) — Define o protocolo como mecanismo de extensibilidade
- [ADR-004: Context como struct com namespace](../adrs/adr-004.md) — Context.initial + Context.steps

## Deliverables
- Estrutura de diretórios criada
- 6 módulos com structs implementadas
- Protocolo StepDefinition definido e implementado para Core.Step
- Unit tests com 80%+ coverage **(REQUIRED)**

## Tests

### Test file: `test/hephaestus/core/context_test.exs`

```elixir
defmodule Hephaestus.Core.ContextTest do
  use ExUnit.Case, async: true

  alias Hephaestus.Core.Context

  describe "new/1" do
    test "creates context with initial data" do
      # Arrange
      initial = %{order_id: 123, items: ["a", "b"]}

      # Act
      context = Context.new(initial)

      # Assert
      assert %Context{initial: %{order_id: 123, items: ["a", "b"]}, steps: %{}} = context
    end

    test "creates context with empty initial data" do
      # Arrange / Act
      context = Context.new(%{})

      # Assert
      assert %Context{initial: %{}, steps: %{}} = context
    end
  end

  describe "put_step_result/3" do
    test "adds step result namespaced by step ref" do
      # Arrange
      context = Context.new(%{order_id: 123})

      # Act
      context = Context.put_step_result(context, :validate, %{valid: true})

      # Assert
      assert %{validate: %{valid: true}} = context.steps
    end

    test "preserves existing step results when adding new one" do
      # Arrange
      context =
        Context.new(%{})
        |> Context.put_step_result(:step_a, %{result: "a"})

      # Act
      context = Context.put_step_result(context, :step_b, %{result: "b"})

      # Assert
      assert %{step_a: %{result: "a"}, step_b: %{result: "b"}} = context.steps
    end

    test "overwrites step result if same ref is used" do
      # Arrange
      context =
        Context.new(%{})
        |> Context.put_step_result(:step_a, %{result: "old"})

      # Act
      context = Context.put_step_result(context, :step_a, %{result: "new"})

      # Assert
      assert %{step_a: %{result: "new"}} = context.steps
    end

    test "does not modify initial data" do
      # Arrange
      context = Context.new(%{order_id: 123})

      # Act
      context = Context.put_step_result(context, :validate, %{valid: true})

      # Assert
      assert %{order_id: 123} = context.initial
    end
  end
end
```

### Test file: `test/hephaestus/core/instance_test.exs`

```elixir
defmodule Hephaestus.Core.InstanceTest do
  use ExUnit.Case, async: true

  alias Hephaestus.Core.{Instance, Context}

  describe "new/2" do
    test "creates instance with workflow module and context" do
      # Arrange
      workflow = MyTestWorkflow
      context = %{order_id: 123}

      # Act
      instance = Instance.new(workflow, context)

      # Assert
      assert %Instance{
        workflow: MyTestWorkflow,
        status: :pending,
        active_steps: active,
        completed_steps: completed
      } = instance
      assert is_binary(instance.id)
      assert %Context{initial: %{order_id: 123}} = instance.context
      assert MapSet.size(active) == 0
      assert MapSet.size(completed) == 0
      assert instance.execution_history == []
    end

    test "generates unique ids" do
      # Arrange / Act
      instance_a = Instance.new(MyTestWorkflow, %{})
      instance_b = Instance.new(MyTestWorkflow, %{})

      # Assert
      refute instance_a.id == instance_b.id
    end

    test "creates instance with default empty context" do
      # Arrange / Act
      instance = Instance.new(MyTestWorkflow)

      # Assert
      assert %Context{initial: %{}, steps: %{}} = instance.context
    end
  end
end
```

### Test file: `test/hephaestus/core/step_test.exs`

```elixir
defmodule Hephaestus.Core.StepTest do
  use ExUnit.Case, async: true

  alias Hephaestus.Core.Step

  describe "struct creation" do
    test "creates step with required fields" do
      # Arrange / Act
      step = %Step{ref: :validate, module: MyApp.Steps.Validate}

      # Assert
      assert step.ref == :validate
      assert step.module == MyApp.Steps.Validate
      assert step.config == nil
      assert step.transitions == nil
    end

    test "creates step with all fields" do
      # Arrange / Act
      step = %Step{
        ref: :notify,
        module: MyApp.Steps.Notify,
        config: %{channel: :email},
        transitions: %{"sent" => :done}
      }

      # Assert
      assert step.config == %{channel: :email}
      assert step.transitions == %{"sent" => :done}
    end

    test "raises when ref is missing" do
      # Assert
      assert_raise ArgumentError, fn ->
        struct!(Step, module: MyApp.Steps.Validate)
      end
    end

    test "raises when module is missing" do
      # Assert
      assert_raise ArgumentError, fn ->
        struct!(Step, ref: :validate)
      end
    end
  end
end
```

### Test file: `test/hephaestus/core/step_definition_test.exs`

```elixir
defmodule Hephaestus.Core.StepDefinitionTest do
  use ExUnit.Case, async: true

  alias Hephaestus.Core.Step
  alias Hephaestus.StepDefinition

  describe "protocol implementation for Core.Step" do
    test "ref/1 returns the step ref" do
      # Arrange
      step = %Step{ref: :validate, module: MyApp.Steps.Validate}

      # Act / Assert
      assert StepDefinition.ref(step) == :validate
    end

    test "module/1 returns the step module" do
      # Arrange
      step = %Step{ref: :validate, module: MyApp.Steps.Validate}

      # Act / Assert
      assert StepDefinition.module(step) == MyApp.Steps.Validate
    end

    test "config/1 returns nil when no config" do
      # Arrange
      step = %Step{ref: :validate, module: MyApp.Steps.Validate}

      # Act / Assert
      assert StepDefinition.config(step) == nil
    end

    test "config/1 returns config map" do
      # Arrange
      step = %Step{ref: :notify, module: MyApp.Steps.Notify, config: %{channel: :email}}

      # Act / Assert
      assert StepDefinition.config(step) == %{channel: :email}
    end

    test "transitions/1 returns transitions map" do
      # Arrange
      step = %Step{
        ref: :validate,
        module: MyApp.Steps.Validate,
        transitions: %{"valid" => :next, "invalid" => :done}
      }

      # Act / Assert
      assert StepDefinition.transitions(step) == %{"valid" => :next, "invalid" => :done}
    end

    test "raises Protocol.UndefinedError for non-implementing struct" do
      # Assert
      assert_raise Protocol.UndefinedError, fn ->
        StepDefinition.ref(%{ref: :test})
      end
    end
  end
end
```

### Test file: `test/hephaestus/core/workflow_test.exs`

```elixir
defmodule Hephaestus.Core.WorkflowTest do
  use ExUnit.Case, async: true

  alias Hephaestus.Core.{Workflow, Step}

  describe "struct creation" do
    test "creates workflow with required fields" do
      # Arrange / Act
      workflow = %Workflow{
        initial_step: :start,
        steps: [
          %Step{ref: :start, module: MyStep, transitions: %{"done" => :finish}},
          %Step{ref: :finish, module: MyEndStep}
        ]
      }

      # Assert
      assert workflow.initial_step == :start
      assert length(workflow.steps) == 2
    end

    test "raises when initial_step is missing" do
      # Assert
      assert_raise ArgumentError, fn ->
        struct!(Workflow, steps: [])
      end
    end

    test "raises when steps is missing" do
      # Assert
      assert_raise ArgumentError, fn ->
        struct!(Workflow, initial_step: :start)
      end
    end
  end
end
```

### Test file: `test/hephaestus/core/execution_entry_test.exs`

```elixir
defmodule Hephaestus.Core.ExecutionEntryTest do
  use ExUnit.Case, async: true

  alias Hephaestus.Core.ExecutionEntry

  describe "struct creation" do
    test "creates entry with required fields" do
      # Arrange
      now = DateTime.utc_now()

      # Act
      entry = %ExecutionEntry{step_ref: :validate, event: "valid", timestamp: now}

      # Assert
      assert entry.step_ref == :validate
      assert entry.event == "valid"
      assert entry.timestamp == now
      assert entry.context_updates == nil
    end

    test "creates entry with context_updates" do
      # Arrange / Act
      entry = %ExecutionEntry{
        step_ref: :validate,
        event: "valid",
        timestamp: DateTime.utc_now(),
        context_updates: %{email_valid: true}
      }

      # Assert
      assert entry.context_updates == %{email_valid: true}
    end

    test "raises when step_ref is missing" do
      # Assert
      assert_raise ArgumentError, fn ->
        struct!(ExecutionEntry, event: "valid", timestamp: DateTime.utc_now())
      end
    end
  end
end
```

- Unit tests:
  - [x] Context.new/1 — creates with initial data
  - [x] Context.new/1 — creates with empty data
  - [x] Context.put_step_result/3 — adds namespaced result
  - [x] Context.put_step_result/3 — preserves existing results
  - [x] Context.put_step_result/3 — overwrites same ref
  - [x] Context.put_step_result/3 — does not modify initial
  - [x] Instance.new/2 — creates with workflow and context
  - [x] Instance.new/2 — generates unique ids
  - [x] Instance.new/1 — default empty context
  - [x] Step struct — required fields
  - [x] Step struct — all fields
  - [x] Step struct — raises on missing ref
  - [x] Step struct — raises on missing module
  - [x] StepDefinition protocol — ref, module, config, transitions dispatch
  - [x] StepDefinition protocol — raises for non-implementing struct
  - [x] Workflow struct — required fields, raises on missing
  - [x] ExecutionEntry struct — required fields, optional context_updates
- Test coverage target: >=80%

## Success Criteria
- All tests passing
- Test coverage >=80%
- Todas as structs usam @enforce_keys
- Protocolo StepDefinition implementado e testado para Core.Step
- Estrutura de diretórios conforme TechSpec
