---
status: pending
domain: Runtime
type: Feature Implementation
scope: Full
complexity: medium
dependencies:
  - task_05
  - task_06
---

# Task 07: Módulo de entrada (`use Hephaestus`)

## Overview

Implementar a macro `use Hephaestus` que gera o módulo de entrada da app consumidora, similar ao pattern do Ecto Repo. Configura storage e runner como adapters, gera `child_spec` com supervision tree interna (Registry, DynamicSupervisor, TaskSupervisor, Storage), e expõe API pública que delega pro runner.

<critical>
- ALWAYS READ the PRD and TechSpec before starting
- REFERENCE TECHSPEC for implementation details — do not duplicate here
- FOCUS ON "WHAT" — describe what needs to be accomplished, not how
- MINIMIZE CODE — show code only to illustrate current structure or problem areas
- TESTS REQUIRED — every task MUST include tests in deliverables
</critical>

<requirements>
- `use Hephaestus, storage: ..., runner: ...` DEVE gerar módulo com API pública
- DEVE gerar `child_spec/1` que starta: Registry, DynamicSupervisor, TaskSupervisor, Storage
- `start_instance/2` e `resume/2` DEVEM delegar pro runner configurado
- Supervision tree DEVE usar nomes derivados do módulo da app (ex: `MyApp.Hephaestus.Registry`)
- Storage e runner padrão DEVEM ser ETS e Local respectivamente
- O módulo gerado DEVE ser adicionável na supervision tree da app: `children = [MyApp.Hephaestus]`
</requirements>

## Subtasks
- [ ] 7.1 Implementar macro `use Hephaestus` com opções de storage e runner
- [ ] 7.2 Gerar `child_spec/1` com supervision tree interna
- [ ] 7.3 Gerar funções `start_instance/2` e `resume/2` delegando pro runner
- [ ] 7.4 Derivar nomes de processos do módulo da app

## Implementation Details

### Relevant Files
- `lib/hephaestus.ex` — macro __using__ principal

### Dependent Files
- `lib/hephaestus/runtime/runner.ex` — Runner behaviour
- `lib/hephaestus/runtime/runner/local.ex` — Runner.Local
- `lib/hephaestus/runtime/storage.ex` — Storage behaviour
- `lib/hephaestus/runtime/storage/ets.ex` — Storage.ETS

### Related ADRs
- [ADR-003: Runner como adapter](../adrs/adr-003.md) — Runner configurável no módulo de entrada

## Deliverables
- Macro `use Hephaestus` funcional
- child_spec com supervision tree completa
- API pública delegando pro runner
- Integration tests com 80%+ coverage **(REQUIRED)**

## Tests

### Test file: `test/hephaestus/entry_module_test.exs`

```elixir
defmodule Hephaestus.EntryModuleTest do
  use ExUnit.Case, async: false

  # Define a test entry module
  defmodule TestHephaestus do
    use Hephaestus,
      storage: Hephaestus.Runtime.Storage.ETS,
      runner: Hephaestus.Runtime.Runner.Local
  end

  setup do
    # Start the supervision tree
    {:ok, pid} = start_supervised(TestHephaestus)
    %{sup: pid}
  end

  describe "supervision tree" do
    test "starts all child processes" do
      # Assert — Registry is running
      assert Process.whereis(TestHephaestus.Registry) != nil ||
             Registry.meta(TestHephaestus.Registry, :custom) != nil

      # Assert — DynamicSupervisor is running
      assert Process.whereis(TestHephaestus.DynamicSupervisor) != nil

      # Assert — TaskSupervisor is running
      assert Process.whereis(TestHephaestus.TaskSupervisor) != nil
    end
  end

  describe "start_instance/2" do
    test "starts a workflow and returns instance id" do
      # Act
      {:ok, instance_id} = TestHephaestus.start_instance(
        Hephaestus.Test.LinearWorkflow,
        %{order_id: 123}
      )

      # Assert
      assert is_binary(instance_id)
    end

    test "workflow completes end-to-end" do
      # Act
      {:ok, instance_id} = TestHephaestus.start_instance(
        Hephaestus.Test.LinearWorkflow,
        %{}
      )
      Process.sleep(100)

      # Assert — verify via storage
      {:ok, instance} = Hephaestus.Runtime.Storage.ETS.get(
        TestHephaestus.Storage,
        instance_id
      )
      assert instance.status == :completed
    end
  end

  describe "resume/2" do
    test "resumes async workflow" do
      # Arrange
      {:ok, id} = TestHephaestus.start_instance(
        Hephaestus.Test.AsyncWorkflow,
        %{}
      )
      Process.sleep(100)

      # Act
      :ok = TestHephaestus.resume(id, "timeout")
      Process.sleep(100)

      # Assert
      {:ok, instance} = Hephaestus.Runtime.Storage.ETS.get(
        TestHephaestus.Storage,
        id
      )
      assert instance.status == :completed
    end
  end

  describe "parallel workflow end-to-end" do
    test "fan-out/fan-in completes via entry module" do
      # Act
      {:ok, id} = TestHephaestus.start_instance(
        Hephaestus.Test.ParallelWorkflow,
        %{}
      )
      Process.sleep(200)

      # Assert
      {:ok, instance} = Hephaestus.Runtime.Storage.ETS.get(
        TestHephaestus.Storage,
        id
      )
      assert instance.status == :completed
      assert MapSet.member?(instance.completed_steps, :join)
    end
  end
end
```

- Integration tests:
  - [x] Supervision tree starts all children
  - [x] start_instance returns instance id
  - [x] Linear workflow completes end-to-end
  - [x] Resume async workflow
  - [x] Parallel workflow fan-out/fan-in end-to-end
- Test coverage target: >=80%

## Success Criteria
- All tests passing
- Test coverage >=80%
- `use Hephaestus` gera módulo com API e supervision tree
- Workflow completo roda end-to-end via módulo de entrada
