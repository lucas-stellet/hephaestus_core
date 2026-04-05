---
status: pending
domain: Runtime
type: Feature Implementation
scope: Full
complexity: high
dependencies:
  - task_04
  - task_05
---

# Task 06: Runner behaviour + Runner.Local

## Overview

Definir o behaviour de Runner e implementar o Runner.Local — um módulo único que implementa o behaviour e é um GenServer. Cada instância de workflow é um processo gerenciado via DynamicSupervisor + Registry. O Runner.Local delega execução para o Engine funcional e usa Task.Supervisor para paralelismo em fan-out.

<critical>
- ALWAYS READ the PRD and TechSpec before starting
- REFERENCE TECHSPEC for implementation details — do not duplicate here
- FOCUS ON "WHAT" — describe what needs to be accomplished, not how
- MINIMIZE CODE — show code only to illustrate current structure or problem areas
- TESTS REQUIRED — every task MUST include tests in deliverables
</critical>

<requirements>
- Behaviour DEVE definir: `start_instance/3`, `resume/2`, `schedule_resume/3`
- Runner.Local DEVE implementar o behaviour E ser GenServer num módulo único
- DEVE registrar instâncias via `{:via, Registry, {Hephaestus.Registry, instance_id}}`
- `start_instance/3` DEVE criar Instance, persistir no Storage, startar GenServer via DynamicSupervisor
- GenServer DEVE chamar `Engine.advance/1` no init via `handle_continue(:advance)`
- Fan-out DEVE usar `Task.Supervisor.async_nolink/3` para paralelismo
- `resume/2` DEVE enviar cast pro GenServer que chama Engine.resume + advance
- `schedule_resume/3` DEVE usar `Process.send_after` para agendar retomada
- GenServer DEVE persistir estado no Storage após cada mudança
- GenServer DEVE parar normalmente quando instância completa (:stop, :normal)
</requirements>

## Subtasks
- [ ] 6.1 Definir behaviour `Hephaestus.Runtime.Runner`
- [ ] 6.2 Implementar Runner.Local com `@behaviour` + `use GenServer`
- [ ] 6.3 Implementar `start_instance/3` com DynamicSupervisor
- [ ] 6.4 Implementar `handle_continue(:advance)` delegando pro Engine
- [ ] 6.5 Implementar `handle_continue(:execute_active)` com Task.Supervisor para fan-out
- [ ] 6.6 Implementar `handle_cast({:resume, event})`
- [ ] 6.7 Implementar `handle_info({:scheduled_resume, step_ref})`
- [ ] 6.8 Implementar `schedule_resume/3` com Process.send_after

## Implementation Details

### Relevant Files
- `lib/hephaestus/runtime/runner.ex` — behaviour definition
- `lib/hephaestus/runtime/runner/local.ex` — Runner.Local implementation

### Dependent Files
- `lib/hephaestus/core/engine.ex` — Engine chamado pelo GenServer
- `lib/hephaestus/runtime/storage/ets.ex` — Storage usado para persistir estado
- `lib/hephaestus/core/instance.ex` — Instance criada e manipulada

### Related ADRs
- [ADR-003: Runner como adapter](../adrs/adr-003.md) — Runner encapsula toda a execução

## Deliverables
- Behaviour Runner definido
- Runner.Local funcional com GenServer
- Integration tests com 80%+ coverage **(REQUIRED)**

## Tests

### Test file: `test/hephaestus/runtime/runner/local_test.exs`

```elixir
defmodule Hephaestus.Runtime.Runner.LocalTest do
  use ExUnit.Case, async: false

  alias Hephaestus.Runtime.Runner.Local, as: RunnerLocal
  alias Hephaestus.Runtime.Storage.ETS, as: ETSStorage

  setup do
    storage_name = :"test_storage_#{System.unique_integer([:positive])}"
    registry_name = :"test_registry_#{System.unique_integer([:positive])}"
    dsup_name = :"test_dsup_#{System.unique_integer([:positive])}"
    tsup_name = :"test_tsup_#{System.unique_integer([:positive])}"

    {:ok, _} = ETSStorage.start_link(name: storage_name)
    {:ok, _} = Registry.start_link(keys: :unique, name: registry_name)
    {:ok, _} = DynamicSupervisor.start_link(name: dsup_name, strategy: :one_for_one)
    {:ok, _} = Task.Supervisor.start_link(name: tsup_name)

    opts = [
      storage: {ETSStorage, storage_name},
      registry: registry_name,
      dynamic_supervisor: dsup_name,
      task_supervisor: tsup_name
    ]

    %{opts: opts, storage: storage_name}
  end

  describe "start_instance/3 — linear workflow" do
    test "starts and completes a sync workflow", %{opts: opts, storage: storage} do
      # Act
      {:ok, instance_id} = RunnerLocal.start_instance(Hephaestus.Test.LinearWorkflow, %{}, opts)

      # Assert — give GenServer time to complete
      Process.sleep(100)
      {:ok, instance} = ETSStorage.get(storage, instance_id)
      assert instance.status == :completed
    end

    test "persists instance in storage", %{opts: opts, storage: storage} do
      # Act
      {:ok, instance_id} = RunnerLocal.start_instance(Hephaestus.Test.LinearWorkflow, %{}, opts)

      # Assert
      Process.sleep(100)
      assert {:ok, _instance} = ETSStorage.get(storage, instance_id)
    end
  end

  describe "start_instance/3 — branching workflow" do
    test "follows correct branch based on context", %{opts: opts, storage: storage} do
      # Act
      {:ok, id} = RunnerLocal.start_instance(
        Hephaestus.Test.BranchWorkflow,
        %{should_approve: true},
        opts
      )

      # Assert
      Process.sleep(100)
      {:ok, instance} = ETSStorage.get(storage, id)
      assert instance.status == :completed
      assert MapSet.member?(instance.completed_steps, :approve)
    end
  end

  describe "start_instance/3 — async workflow" do
    test "pauses at async step", %{opts: opts, storage: storage} do
      # Act
      {:ok, id} = RunnerLocal.start_instance(Hephaestus.Test.AsyncWorkflow, %{}, opts)

      # Assert
      Process.sleep(100)
      {:ok, instance} = ETSStorage.get(storage, id)
      assert instance.status == :waiting
    end
  end

  describe "resume/2" do
    test "resumes paused instance and completes", %{opts: opts, storage: storage} do
      # Arrange
      {:ok, id} = RunnerLocal.start_instance(Hephaestus.Test.AsyncWorkflow, %{}, opts)
      Process.sleep(100)

      # Act
      :ok = RunnerLocal.resume(id, "timeout")
      Process.sleep(100)

      # Assert
      {:ok, instance} = ETSStorage.get(storage, id)
      assert instance.status == :completed
    end

    test "returns error for nonexistent instance", %{opts: _opts} do
      # Act / Assert
      assert {:error, :instance_not_found} = RunnerLocal.resume("nonexistent", "event")
    end
  end

  describe "schedule_resume/3" do
    test "resumes instance after delay", %{opts: opts, storage: storage} do
      # Arrange
      {:ok, id} = RunnerLocal.start_instance(Hephaestus.Test.AsyncWorkflow, %{}, opts)
      Process.sleep(100)

      # Act
      {:ok, _ref} = RunnerLocal.schedule_resume(id, :wait, 50)
      Process.sleep(200)

      # Assert
      {:ok, instance} = ETSStorage.get(storage, id)
      assert instance.status == :completed
    end
  end

  describe "start_instance/3 — parallel workflow (fan-out/fan-in)" do
    test "executes parallel branches and joins", %{opts: opts, storage: storage} do
      # Act
      {:ok, id} = RunnerLocal.start_instance(Hephaestus.Test.ParallelWorkflow, %{}, opts)

      # Assert
      Process.sleep(200)
      {:ok, instance} = ETSStorage.get(storage, id)
      assert instance.status == :completed
      assert MapSet.member?(instance.completed_steps, :branch_a)
      assert MapSet.member?(instance.completed_steps, :branch_b)
      assert MapSet.member?(instance.completed_steps, :join)
    end
  end

  describe "GenServer lifecycle" do
    test "GenServer stops after workflow completes", %{opts: opts} do
      # Arrange
      {:ok, id} = RunnerLocal.start_instance(Hephaestus.Test.LinearWorkflow, %{}, opts)
      Process.sleep(100)

      # Assert — process should be gone
      registry = opts[:registry]
      assert Registry.lookup(registry, id) == []
    end

    test "registers in Registry while running", %{opts: opts} do
      # Arrange
      {:ok, id} = RunnerLocal.start_instance(Hephaestus.Test.AsyncWorkflow, %{}, opts)
      Process.sleep(100)

      # Assert — process should be alive (waiting)
      registry = opts[:registry]
      assert [{pid, _}] = Registry.lookup(registry, id)
      assert Process.alive?(pid)
    end
  end
end
```

- Integration tests:
  - [x] Linear workflow starts and completes
  - [x] Persists instance in storage
  - [x] Branch workflow follows correct branch
  - [x] Async workflow pauses
  - [x] Resume resumes and completes
  - [x] Resume returns error for nonexistent
  - [x] Schedule_resume resumes after delay
  - [x] Parallel workflow fan-out/fan-in
  - [x] GenServer stops after completion
  - [x] Registers in Registry while running
- Test coverage target: >=80%

## Success Criteria
- All tests passing
- Test coverage >=80%
- Runner.Local funciona como behaviour + GenServer num módulo
- Fan-out usa Task.Supervisor para paralelismo real
- Instâncias registradas via Registry
