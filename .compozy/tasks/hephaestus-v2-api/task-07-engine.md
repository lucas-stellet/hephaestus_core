# Task 07: Adaptar Engine para nova API

## Objetivo

Remover dependencia de `StepDefinition` protocol. Engine passa a trabalhar com modules diretamente, busca config de `step_configs`, chama `workflow.start()` e `workflow.transit()`, e grava context com snake_case keys.

## Arquivos

- `lib/hephaestus/core/engine.ex` — reescrever funcoes mantendo mesma estrutura

## Depende de

- Task 04 (Instance com step_configs)
- Task 05 (Step struct e StepDefinition removidos)
- Task 06 (Workflow macro gerando __predecessors__)

## Mudancas

### ensure_started/1
```elixir
# Antes: workflow.definition().initial_step
# Depois: workflow.start()
defp ensure_started(%Instance{status: :pending} = instance) do
  start = instance.workflow.start()
  {module, config} = normalize_start(start)
  %{instance |
    status: :running,
    current_step: module,
    active_steps: MapSet.put(instance.active_steps, module),
    step_configs: maybe_put_config(instance.step_configs, module, config)
  }
end
```

### execute_step/2
```elixir
# Antes: recebe step_def, usa StepDefinition.module() e StepDefinition.config()
# Depois: recebe module, busca config de step_configs, valida function_exported?
def execute_step(%Instance{} = instance, step_module) when is_atom(step_module) do
  unless function_exported?(step_module, :execute, 3) do
    raise "#{inspect(step_module)} must implement execute/3"
  end
  config = Map.get(instance.step_configs, step_module)
  step_module.execute(instance, config, instance.context)
end
```

### complete_step/4
```elixir
# Grava context com snake_case key, limpa step_configs
def complete_step(%Instance{} = instance, step_module, _event, context_updates) do
  context_key = module_to_context_key(step_module)
  %{instance |
    active_steps: MapSet.delete(instance.active_steps, step_module),
    completed_steps: MapSet.put(instance.completed_steps, step_module),
    context: Context.put_step_result(instance.context, context_key, context_updates),
    step_configs: Map.delete(instance.step_configs, step_module)
  }
end
```

### activate_transitions/3
```elixir
# Antes: busca transitions via StepDefinition.transitions()
# Depois: chama workflow.transit(from, event) diretamente
def activate_transitions(%Instance{} = instance, from_module, event) do
  case resolve_transit(instance.workflow, from_module, event, instance) do
    nil -> instance
    target when is_atom(target) -> maybe_activate_step(instance, target, nil)
    {target, config} -> maybe_activate_step(instance, target, config)
    targets when is_list(targets) ->
      Enum.reduce(targets, instance, fn
        {mod, cfg}, acc -> maybe_activate_step(acc, mod, cfg)
        mod, acc -> maybe_activate_step(acc, mod, nil)
      end)
  end
end
```

### maybe_activate_step/3 (novo — com config)
```elixir
defp maybe_activate_step(%Instance{} = instance, step_module, config) do
  predecessors = instance.workflow.__predecessors__(step_module)
  if MapSet.subset?(predecessors, instance.completed_steps) do
    %{instance |
      active_steps: MapSet.put(instance.active_steps, step_module),
      step_configs: maybe_put_config(instance.step_configs, step_module, config)
    }
  else
    instance
  end
end
```

### module_to_context_key/1 (nova)
```elixir
defp module_to_context_key(module) do
  if function_exported?(module, :step_key, 0) do
    module.step_key()
  else
    module |> Module.split() |> List.last() |> Macro.underscore() |> String.to_atom()
  end
end
```

## Test Skeleton

**Arquivo:** `test/hephaestus/core/engine_v2_test.exs`

```elixir
defmodule Hephaestus.Core.EngineV2Test do
  use ExUnit.Case, async: true

  alias Hephaestus.Core.{Context, Engine, Instance}

  # Test workflows definidos em test/support/test_workflows_v2.ex

  describe "advance/1" do
    test "pending instance becomes running with start module active" do
      # Arrange
      instance = Instance.new(Hephaestus.Test.V2.LinearWorkflow, %{})

      # Act
      {:ok, advanced} = Engine.advance(instance)

      # Assert
      assert advanced.status == :running
      assert MapSet.member?(advanced.active_steps, Hephaestus.Test.V2.StepA)
    end

    test "start/0 returning {module, config} stores config in step_configs" do
      # Arrange
      instance = Instance.new(Hephaestus.Test.V2.ConfigStartWorkflow, %{})

      # Act
      {:ok, advanced} = Engine.advance(instance)

      # Assert
      assert advanced.step_configs[Hephaestus.Test.V2.ConfigStep] == %{timeout: 5000}
    end
  end

  describe "execute_step/2" do
    test "calls module.execute/3 with config from step_configs" do
      # Arrange
      instance = %{Instance.new(Hephaestus.Test.V2.LinearWorkflow, %{}) |
        step_configs: %{Hephaestus.Test.V2.ConfigStep => %{timeout: 5000}}}

      # Act
      result = Engine.execute_step(instance, Hephaestus.Test.V2.ConfigStep)

      # Assert
      assert {:ok, :done, %{config_received: %{timeout: 5000}}} = result
    end

    test "passes nil config when step has no config" do
      # Arrange
      instance = Instance.new(Hephaestus.Test.V2.LinearWorkflow, %{})

      # Act
      result = Engine.execute_step(instance, Hephaestus.Test.V2.StepA)

      # Assert
      assert {:ok, :done} = result
    end

    test "raises when module does not implement execute/3" do
      # Arrange
      instance = Instance.new(Hephaestus.Test.V2.LinearWorkflow, %{})

      # Act & Assert
      assert_raise RuntimeError, ~r/must implement execute\/3/, fn ->
        Engine.execute_step(instance, NotARealStep)
      end
    end
  end

  describe "complete_step/4" do
    test "moves step from active to completed and stores context with snake_case key" do
      # Arrange
      instance = %{Instance.new(Hephaestus.Test.V2.LinearWorkflow, %{}) |
        active_steps: MapSet.new([Hephaestus.Test.V2.StepA]),
        status: :running}

      # Act
      completed = Engine.complete_step(instance, Hephaestus.Test.V2.StepA, :done, %{item_count: 3})

      # Assert
      refute MapSet.member?(completed.active_steps, Hephaestus.Test.V2.StepA)
      assert MapSet.member?(completed.completed_steps, Hephaestus.Test.V2.StepA)
      assert completed.context.steps.step_a.item_count == 3
    end

    test "cleans up step_configs after completion" do
      # Arrange
      instance = %{Instance.new(Hephaestus.Test.V2.LinearWorkflow, %{}) |
        active_steps: MapSet.new([Hephaestus.Test.V2.ConfigStep]),
        step_configs: %{Hephaestus.Test.V2.ConfigStep => %{timeout: 5000}},
        status: :running}

      # Act
      completed = Engine.complete_step(instance, Hephaestus.Test.V2.ConfigStep, :done, %{})

      # Assert
      refute Map.has_key?(completed.step_configs, Hephaestus.Test.V2.ConfigStep)
    end

    test "uses step_key/0 override for context key" do
      # Arrange — Hephaestus.Test.V2.StepWithCustomKey implements step_key/0 -> :custom_key
      instance = %{Instance.new(Hephaestus.Test.V2.LinearWorkflow, %{}) |
        active_steps: MapSet.new([Hephaestus.Test.V2.StepWithCustomKey]),
        status: :running}

      # Act
      completed = Engine.complete_step(instance, Hephaestus.Test.V2.StepWithCustomKey, :done, %{data: true})

      # Assert
      assert completed.context.steps.custom_key.data == true
    end
  end

  describe "activate_transitions/3" do
    test "activates next step from transit/2" do
      # Arrange
      instance = %{Instance.new(Hephaestus.Test.V2.LinearWorkflow, %{}) |
        completed_steps: MapSet.new([Hephaestus.Test.V2.StepA]),
        status: :running}

      # Act
      activated = Engine.activate_transitions(instance, Hephaestus.Test.V2.StepA, :done)

      # Assert
      assert MapSet.member?(activated.active_steps, Hephaestus.Test.V2.StepB)
    end

    test "activates multiple steps on fan-out" do
      # Arrange
      instance = %{Instance.new(Hephaestus.Test.V2.FanOutWorkflow, %{}) |
        completed_steps: MapSet.new([Hephaestus.Test.V2.StepA]),
        status: :running}

      # Act
      activated = Engine.activate_transitions(instance, Hephaestus.Test.V2.StepA, :done)

      # Assert
      assert MapSet.member?(activated.active_steps, Hephaestus.Test.V2.ParallelA)
      assert MapSet.member?(activated.active_steps, Hephaestus.Test.V2.ParallelB)
    end

    test "fan-in waits for all predecessors before activating join" do
      # Arrange — only ParallelA completed, ParallelB still pending
      instance = %{Instance.new(Hephaestus.Test.V2.FanOutWorkflow, %{}) |
        completed_steps: MapSet.new([Hephaestus.Test.V2.StepA, Hephaestus.Test.V2.ParallelA]),
        status: :running}

      # Act
      activated = Engine.activate_transitions(instance, Hephaestus.Test.V2.ParallelA, :done)

      # Assert — JoinStep NOT activated because ParallelB not completed
      refute MapSet.member?(activated.active_steps, Hephaestus.Test.V2.JoinStep)
    end

    test "fan-in activates join when all predecessors completed" do
      # Arrange — both ParallelA and ParallelB completed
      instance = %{Instance.new(Hephaestus.Test.V2.FanOutWorkflow, %{}) |
        completed_steps: MapSet.new([Hephaestus.Test.V2.StepA, Hephaestus.Test.V2.ParallelA, Hephaestus.Test.V2.ParallelB]),
        status: :running}

      # Act
      activated = Engine.activate_transitions(instance, Hephaestus.Test.V2.ParallelB, :done)

      # Assert
      assert MapSet.member?(activated.active_steps, Hephaestus.Test.V2.JoinStep)
    end

    test "stores config when transit returns {module, config}" do
      # Arrange
      instance = %{Instance.new(Hephaestus.Test.V2.ConfigTransitWorkflow, %{}) |
        completed_steps: MapSet.new([Hephaestus.Test.V2.StepA]),
        status: :running}

      # Act
      activated = Engine.activate_transitions(instance, Hephaestus.Test.V2.StepA, :done)

      # Assert
      assert activated.step_configs[Hephaestus.Test.V2.ConfigStep] == %{timeout: 5000}
    end
  end

  describe "resume_step/3" do
    test "resumes waiting step with atom event" do
      # Arrange
      instance = %{Instance.new(Hephaestus.Test.V2.AsyncWorkflow, %{}) |
        active_steps: MapSet.new([Hephaestus.Test.V2.AsyncStep]),
        current_step: Hephaestus.Test.V2.AsyncStep,
        status: :waiting}

      # Act
      resumed = Engine.resume_step(instance, Hephaestus.Test.V2.AsyncStep, :timeout)

      # Assert
      assert resumed.status == :running
      assert MapSet.member?(resumed.completed_steps, Hephaestus.Test.V2.AsyncStep)
    end
  end

  describe "check_completion/1" do
    test "marks instance as completed when no active steps" do
      # Arrange
      instance = %{Instance.new(Hephaestus.Test.V2.LinearWorkflow, %{}) |
        active_steps: MapSet.new(),
        completed_steps: MapSet.new([Hephaestus.Test.V2.StepA, Hephaestus.Test.V2.StepB, Hephaestus.Steps.End]),
        status: :running}

      # Act
      checked = Engine.check_completion(instance)

      # Assert
      assert checked.status == :completed
    end
  end

  describe "module_to_context_key/1" do
    test "converts module last segment to snake_case atom" do
      # Este teste valida indiretamente via complete_step
      # StepA -> :step_a, ValidateOrder -> :validate_order
      instance = %{Instance.new(Hephaestus.Test.V2.LinearWorkflow, %{}) |
        active_steps: MapSet.new([Hephaestus.Test.V2.StepA]),
        status: :running}

      completed = Engine.complete_step(instance, Hephaestus.Test.V2.StepA, :done, %{x: 1})
      assert completed.context.steps.step_a == %{x: 1}
    end
  end
end
```

## Test Support Necessario

**Arquivo:** `test/support/test_workflows_v2.ex`

Criar workflow modules de teste com a nova API:

```elixir
defmodule Hephaestus.Test.V2.LinearWorkflow do
  use Hephaestus.Workflow

  @impl true
  def start, do: Hephaestus.Test.V2.StepA

  @impl true
  def transit(Hephaestus.Test.V2.StepA, :done), do: Hephaestus.Test.V2.StepB
  def transit(Hephaestus.Test.V2.StepB, :done), do: Hephaestus.Steps.End
end

defmodule Hephaestus.Test.V2.FanOutWorkflow do
  use Hephaestus.Workflow

  @impl true
  def start, do: Hephaestus.Test.V2.StepA

  @impl true
  def transit(Hephaestus.Test.V2.StepA, :done), do: [Hephaestus.Test.V2.ParallelA, Hephaestus.Test.V2.ParallelB]
  def transit(Hephaestus.Test.V2.ParallelA, :done), do: Hephaestus.Test.V2.JoinStep
  def transit(Hephaestus.Test.V2.ParallelB, :done), do: Hephaestus.Test.V2.JoinStep
  def transit(Hephaestus.Test.V2.JoinStep, :done), do: Hephaestus.Steps.End
end

defmodule Hephaestus.Test.V2.AsyncWorkflow do
  use Hephaestus.Workflow

  @impl true
  def start, do: Hephaestus.Test.V2.StepA

  @impl true
  def transit(Hephaestus.Test.V2.StepA, :done), do: Hephaestus.Test.V2.AsyncStep
  def transit(Hephaestus.Test.V2.AsyncStep, :timeout), do: Hephaestus.Test.V2.StepB
  def transit(Hephaestus.Test.V2.StepB, :done), do: Hephaestus.Steps.End
end

defmodule Hephaestus.Test.V2.ConfigStartWorkflow do
  use Hephaestus.Workflow

  @impl true
  def start, do: {Hephaestus.Test.V2.ConfigStep, %{timeout: 5000}}

  @impl true
  def transit(Hephaestus.Test.V2.ConfigStep, :done), do: Hephaestus.Steps.End
end

defmodule Hephaestus.Test.V2.ConfigTransitWorkflow do
  use Hephaestus.Workflow

  @impl true
  def start, do: Hephaestus.Test.V2.StepA

  @impl true
  def transit(Hephaestus.Test.V2.StepA, :done), do: {Hephaestus.Test.V2.ConfigStep, %{timeout: 5000}}
  def transit(Hephaestus.Test.V2.ConfigStep, :done), do: Hephaestus.Steps.End
end

defmodule Hephaestus.Test.V2.BranchWorkflow do
  use Hephaestus.Workflow

  @impl true
  def start, do: Hephaestus.Test.V2.BranchStep

  @impl true
  def transit(Hephaestus.Test.V2.BranchStep, :approved), do: Hephaestus.Test.V2.ApproveStep
  def transit(Hephaestus.Test.V2.BranchStep, :rejected), do: Hephaestus.Test.V2.RejectStep
  def transit(Hephaestus.Test.V2.ApproveStep, :done), do: Hephaestus.Steps.End
  def transit(Hephaestus.Test.V2.RejectStep, :done), do: Hephaestus.Steps.End
end

defmodule Hephaestus.Test.V2.EventWorkflow do
  use Hephaestus.Workflow

  @impl true
  def start, do: Hephaestus.Test.V2.StepA

  @impl true
  def transit(Hephaestus.Test.V2.StepA, :done), do: Hephaestus.Test.V2.WaitForEventStep
  def transit(Hephaestus.Test.V2.WaitForEventStep, :received), do: Hephaestus.Test.V2.StepB
  def transit(Hephaestus.Test.V2.StepB, :done), do: Hephaestus.Steps.End
end

defmodule Hephaestus.Test.V2.DynamicWorkflow do
  use Hephaestus.Workflow

  @impl true
  def start, do: Hephaestus.Test.V2.StepA

  @impl true
  @targets [Hephaestus.Test.V2.StepB, Hephaestus.Test.V2.StepC]
  def transit(Hephaestus.Test.V2.StepA, :done, ctx) do
    if ctx.initial[:use_b], do: Hephaestus.Test.V2.StepB, else: Hephaestus.Test.V2.StepC
  end

  def transit(Hephaestus.Test.V2.StepB, :done), do: Hephaestus.Steps.End
  def transit(Hephaestus.Test.V2.StepC, :done), do: Hephaestus.Steps.End
end
```

Adicionar step com step_key/0 override em `test/support/test_steps_v2.ex`:

```elixir
defmodule Hephaestus.Test.V2.StepWithCustomKey do
  @behaviour Hephaestus.Steps.Step
  @impl true
  def events, do: [:done]
  @impl true
  def step_key, do: :custom_key
  @impl true
  def execute(_instance, _config, _context), do: {:ok, :done}
end
```

## Sequencia TDD

1. RED: "pending instance becomes running with start module active" — falha porque ensure_started usa definition()
2. GREEN: reescrever ensure_started pra chamar workflow.start()
3. RED: "start/0 returning {module, config} stores config" — falha porque step_configs nao e populado
4. GREEN: implementar normalize_start e maybe_put_config
5. RED: "calls module.execute/3 with config from step_configs" — falha porque execute_step usa StepDefinition
6. GREEN: reescrever execute_step pra receber module e buscar config de step_configs
7. RED: "raises when module does not implement execute/3" — falha ate adicionar function_exported? check
8. GREEN: adicionar guard
9. RED: "moves step from active to completed and stores context with snake_case key" — falha porque complete_step usa atom ref
10. GREEN: implementar module_to_context_key, limpar step_configs em complete_step
11. RED: "activates next step from transit/2" — falha porque activate_transitions usa StepDefinition.transitions
12. GREEN: implementar resolve_transit chamando workflow.transit diretamente
13. RED: testes de fan-out, fan-in, config transit, resume — implementar incrementalmente
14. REFACTOR: limpar imports, remover alias StepDefinition
