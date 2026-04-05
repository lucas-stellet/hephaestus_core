---
status: pending
domain: Core
type: Feature Implementation
scope: Full
complexity: medium
dependencies:
  - task_01
---

# Task 02: Step behaviour + Built-in steps (End, Debug, Wait, WaitForEvent)

## Overview

Definir o behaviour `Hephaestus.Steps.Step` com o callback `execute/3` e implementar os 4 steps built-in da lib. Estes são os únicos steps que a lib fornece — qualquer outro é responsabilidade da app consumidora. Cada step é testado de forma isolada contra o behaviour, sem processos OTP.

<critical>
- ALWAYS READ the PRD and TechSpec before starting
- REFERENCE TECHSPEC for implementation details — do not duplicate here
- FOCUS ON "WHAT" — describe what needs to be accomplished, not how
- MINIMIZE CODE — show code only to illustrate current structure or problem areas
- TESTS REQUIRED — every task MUST include tests in deliverables
</critical>

<requirements>
- Behaviour `Hephaestus.Steps.Step` DEVE definir callback `execute(instance, config, context)`
- Return types: `{:ok, event}`, `{:ok, event, context_updates}`, `{:async}`, `{:error, reason}`
- `End` DEVE retornar `{:ok, "completed"}`
- `Debug` DEVE logar context.initial, context.steps e execution_history via Logger.debug e retornar `{:ok, "completed"}`
- `Wait` DEVE retornar `{:async}` e expor função `delay_ms/1` para converter config de duração
- `WaitForEvent` DEVE retornar `{:async}`
- Wait config DEVE aceitar `duration` (integer) e `unit` (:second, :minute, :hour, :day)
- WaitForEvent config DEVE aceitar `event_name` (string) e `timeout_ms` (optional integer)
</requirements>

## Subtasks
- [ ] 2.1 Definir behaviour `Hephaestus.Steps.Step` com callback `execute/3`
- [ ] 2.2 Implementar `Hephaestus.Steps.End`
- [ ] 2.3 Implementar `Hephaestus.Steps.Debug`
- [ ] 2.4 Implementar `Hephaestus.Steps.Wait` com `delay_ms/1`
- [ ] 2.5 Implementar `Hephaestus.Steps.WaitForEvent`

## Implementation Details

### Relevant Files
- `lib/hephaestus/steps/step.ex` — behaviour definition
- `lib/hephaestus/steps/end_step.ex` — step terminal
- `lib/hephaestus/steps/debug.ex` — step de debug
- `lib/hephaestus/steps/wait.ex` — step de pausa por duração
- `lib/hephaestus/steps/wait_for_event.ex` — step de pausa por evento

### Dependent Files
- `lib/hephaestus/core/instance.ex` — Instance.t() usado no callback
- `lib/hephaestus/core/context.ex` — Context.t() usado no callback

## Deliverables
- Behaviour definido com callback e types
- 4 steps built-in implementados
- Unit tests com 80%+ coverage **(REQUIRED)**

## Tests

### Test file: `test/hephaestus/steps/end_step_test.exs`

```elixir
defmodule Hephaestus.Steps.EndStepTest do
  use ExUnit.Case, async: true

  alias Hephaestus.Steps.End, as: EndStep
  alias Hephaestus.Core.{Instance, Context}

  describe "execute/3" do
    test "returns completed event" do
      # Arrange
      instance = Instance.new(TestWorkflow, %{})
      context = Context.new(%{order_id: 123})

      # Act
      result = EndStep.execute(instance, nil, context)

      # Assert
      assert {:ok, "completed"} = result
    end

    test "ignores config" do
      # Arrange
      instance = Instance.new(TestWorkflow, %{})
      context = Context.new(%{})

      # Act
      result = EndStep.execute(instance, %{some: "config"}, context)

      # Assert
      assert {:ok, "completed"} = result
    end
  end
end
```

### Test file: `test/hephaestus/steps/debug_test.exs`

```elixir
defmodule Hephaestus.Steps.DebugTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Hephaestus.Steps.Debug
  alias Hephaestus.Core.{Instance, Context, ExecutionEntry}

  describe "execute/3" do
    test "returns completed event" do
      # Arrange
      instance = Instance.new(TestWorkflow, %{order_id: 123})
      context = Context.new(%{order_id: 123})

      # Act
      result = Debug.execute(instance, nil, context)

      # Assert
      assert {:ok, "completed"} = result
    end

    test "logs context initial data" do
      # Arrange
      instance = Instance.new(TestWorkflow, %{order_id: 123})
      context = Context.new(%{order_id: 123})

      # Act
      log = capture_log(fn ->
        Debug.execute(instance, nil, context)
      end)

      # Assert
      assert log =~ "order_id"
      assert log =~ "123"
    end

    test "logs step results from context" do
      # Arrange
      instance = Instance.new(TestWorkflow, %{})
      context =
        Context.new(%{})
        |> Context.put_step_result(:validate, %{valid: true})

      # Act
      log = capture_log(fn ->
        Debug.execute(instance, nil, context)
      end)

      # Assert
      assert log =~ "validate"
      assert log =~ "valid"
    end

    test "logs execution history" do
      # Arrange
      entry = %ExecutionEntry{
        step_ref: :validate,
        event: "valid",
        timestamp: ~U[2026-01-01 00:00:00Z]
      }
      instance = %{Instance.new(TestWorkflow, %{}) | execution_history: [entry]}
      context = Context.new(%{})

      # Act
      log = capture_log(fn ->
        Debug.execute(instance, nil, context)
      end)

      # Assert
      assert log =~ "validate"
      assert log =~ "valid"
    end
  end
end
```

### Test file: `test/hephaestus/steps/wait_test.exs`

```elixir
defmodule Hephaestus.Steps.WaitTest do
  use ExUnit.Case, async: true

  alias Hephaestus.Steps.Wait
  alias Hephaestus.Core.{Instance, Context}

  describe "execute/3" do
    test "returns async for valid config" do
      # Arrange
      instance = Instance.new(TestWorkflow, %{})
      config = %{duration: 30, unit: :minute}
      context = Context.new(%{})

      # Act
      result = Wait.execute(instance, config, context)

      # Assert
      assert {:async} = result
    end
  end

  describe "delay_ms/1" do
    test "converts seconds to milliseconds" do
      # Arrange
      config = %{duration: 10, unit: :second}

      # Act / Assert
      assert Wait.delay_ms(config) == 10_000
    end

    test "converts minutes to milliseconds" do
      # Arrange
      config = %{duration: 5, unit: :minute}

      # Act / Assert
      assert Wait.delay_ms(config) == 300_000
    end

    test "converts hours to milliseconds" do
      # Arrange
      config = %{duration: 2, unit: :hour}

      # Act / Assert
      assert Wait.delay_ms(config) == 7_200_000
    end

    test "converts days to milliseconds" do
      # Arrange
      config = %{duration: 1, unit: :day}

      # Act / Assert
      assert Wait.delay_ms(config) == 86_400_000
    end
  end
end
```

### Test file: `test/hephaestus/steps/wait_for_event_test.exs`

```elixir
defmodule Hephaestus.Steps.WaitForEventTest do
  use ExUnit.Case, async: true

  alias Hephaestus.Steps.WaitForEvent
  alias Hephaestus.Core.{Instance, Context}

  describe "execute/3" do
    test "returns async" do
      # Arrange
      instance = Instance.new(TestWorkflow, %{})
      config = %{event_name: "payment_confirmed"}
      context = Context.new(%{})

      # Act
      result = WaitForEvent.execute(instance, config, context)

      # Assert
      assert {:async} = result
    end

    test "returns async with timeout config" do
      # Arrange
      instance = Instance.new(TestWorkflow, %{})
      config = %{event_name: "payment_confirmed", timeout_ms: 60_000}
      context = Context.new(%{})

      # Act
      result = WaitForEvent.execute(instance, config, context)

      # Assert
      assert {:async} = result
    end
  end
end
```

- Unit tests:
  - [x] End.execute/3 — returns "completed"
  - [x] End.execute/3 — ignores config
  - [x] Debug.execute/3 — returns "completed"
  - [x] Debug.execute/3 — logs initial data
  - [x] Debug.execute/3 — logs step results
  - [x] Debug.execute/3 — logs execution history
  - [x] Wait.execute/3 — returns {:async}
  - [x] Wait.delay_ms/1 — seconds, minutes, hours, days conversion
  - [x] WaitForEvent.execute/3 — returns {:async}
  - [x] WaitForEvent.execute/3 — works with timeout config
- Test coverage target: >=80%

## Success Criteria
- All tests passing
- Test coverage >=80%
- Todos os steps implementam o behaviour
- Wait.delay_ms/1 converte corretamente todas as unidades
