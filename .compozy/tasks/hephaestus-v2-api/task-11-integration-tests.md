# Task 11: Integration tests — runtime OTP end-to-end

## Objetivo

Testar fluxos completos via Runner.Local com supervision tree: start → execute → complete, async, events, fan-out, crash recovery. Valida que o runtime funciona com a nova API v2.

## Arquivo

- `test/hephaestus/runtime/runner/local_v2_test.exs`

## Depende de

- Tasks 08, 09, 10 (tudo implementado e testes unitarios passando)

## Test Skeleton

```elixir
defmodule Hephaestus.Runtime.Runner.LocalV2Test do
  use ExUnit.Case, async: false

  # Setup supervision tree
  setup do
    name = :"test_heph_#{System.unique_integer([:positive])}"

    registry = Module.concat(name, Registry)
    dynamic_supervisor = Module.concat(name, DynamicSupervisor)
    task_supervisor = Module.concat(name, TaskSupervisor)
    storage_name = Module.concat(name, Storage)

    children = [
      {Registry, keys: :unique, name: registry},
      {DynamicSupervisor, name: dynamic_supervisor, strategy: :one_for_one},
      {Task.Supervisor, name: task_supervisor},
      {Hephaestus.Runtime.Storage.ETS, name: storage_name}
    ]

    {:ok, sup} = Supervisor.start_link(children, strategy: :one_for_one)

    opts = [
      storage: {Hephaestus.Runtime.Storage.ETS, storage_name},
      registry: registry,
      dynamic_supervisor: dynamic_supervisor,
      task_supervisor: task_supervisor
    ]

    on_exit(fn -> Supervisor.stop(sup) end)

    %{opts: opts, storage: {Hephaestus.Runtime.Storage.ETS, storage_name}}
  end

  describe "linear workflow end-to-end" do
    test "start_instance executes to completion", %{opts: opts, storage: storage} do
      # Arrange & Act
      {:ok, instance_id} = Hephaestus.Runtime.Runner.Local.start_instance(
        Hephaestus.Test.V2.LinearWorkflow,
        %{data: "test"},
        opts
      )

      # Assert — wait for completion
      Process.sleep(100)
      {:ok, instance} = apply(elem(storage, 0), :get, [elem(storage, 1), instance_id])
      assert instance.status == :completed
      assert MapSet.member?(instance.completed_steps, Hephaestus.Test.V2.StepA)
      assert MapSet.member?(instance.completed_steps, Hephaestus.Test.V2.StepB)
      assert MapSet.member?(instance.completed_steps, Hephaestus.Steps.End)
    end
  end

  describe "branch workflow end-to-end" do
    test "follows approved branch to completion", %{opts: opts, storage: storage} do
      # Arrange & Act
      {:ok, instance_id} = Hephaestus.Runtime.Runner.Local.start_instance(
        Hephaestus.Test.V2.BranchWorkflow,
        %{should_approve: true},
        opts
      )

      # Assert
      Process.sleep(100)
      {:ok, instance} = apply(elem(storage, 0), :get, [elem(storage, 1), instance_id])
      assert instance.status == :completed
      assert MapSet.member?(instance.completed_steps, Hephaestus.Test.V2.ApproveStep)
      refute MapSet.member?(instance.completed_steps, Hephaestus.Test.V2.RejectStep)
    end

    test "follows rejected branch to completion", %{opts: opts, storage: storage} do
      # Arrange & Act
      {:ok, instance_id} = Hephaestus.Runtime.Runner.Local.start_instance(
        Hephaestus.Test.V2.BranchWorkflow,
        %{should_approve: false},
        opts
      )

      # Assert
      Process.sleep(100)
      {:ok, instance} = apply(elem(storage, 0), :get, [elem(storage, 1), instance_id])
      assert instance.status == :completed
      assert MapSet.member?(instance.completed_steps, Hephaestus.Test.V2.RejectStep)
      refute MapSet.member?(instance.completed_steps, Hephaestus.Test.V2.ApproveStep)
    end
  end

  describe "fan-out workflow end-to-end" do
    test "parallel steps execute and converge at join", %{opts: opts, storage: storage} do
      # Arrange & Act
      {:ok, instance_id} = Hephaestus.Runtime.Runner.Local.start_instance(
        Hephaestus.Test.V2.FanOutWorkflow,
        %{},
        opts
      )

      # Assert
      Process.sleep(200)
      {:ok, instance} = apply(elem(storage, 0), :get, [elem(storage, 1), instance_id])
      assert instance.status == :completed
      assert MapSet.member?(instance.completed_steps, Hephaestus.Test.V2.ParallelA)
      assert MapSet.member?(instance.completed_steps, Hephaestus.Test.V2.ParallelB)
      assert MapSet.member?(instance.completed_steps, Hephaestus.Test.V2.JoinStep)
    end
  end

  describe "async workflow with resume" do
    test "pauses at async step and resumes with atom event", %{opts: opts, storage: storage} do
      # Arrange
      {:ok, instance_id} = Hephaestus.Runtime.Runner.Local.start_instance(
        Hephaestus.Test.V2.AsyncWorkflow,
        %{},
        opts
      )

      # Wait for workflow to reach async step
      Process.sleep(100)
      {:ok, instance} = apply(elem(storage, 0), :get, [elem(storage, 1), instance_id])
      assert instance.status == :waiting

      # Act — resume with atom event
      :ok = Hephaestus.Runtime.Runner.Local.resume(instance_id, :timeout)

      # Assert
      Process.sleep(100)
      {:ok, instance} = apply(elem(storage, 0), :get, [elem(storage, 1), instance_id])
      assert instance.status == :completed
    end
  end

  describe "event workflow with external resume" do
    test "waits for event and resumes on external trigger", %{opts: opts, storage: storage} do
      # Arrange
      {:ok, instance_id} = Hephaestus.Runtime.Runner.Local.start_instance(
        Hephaestus.Test.V2.EventWorkflow,
        %{},
        opts
      )

      # Wait for workflow to reach wait_for_event step
      Process.sleep(100)
      {:ok, instance} = apply(elem(storage, 0), :get, [elem(storage, 1), instance_id])
      assert instance.status == :waiting

      # Act — resume with received event
      :ok = Hephaestus.Runtime.Runner.Local.resume(instance_id, :received)

      # Assert
      Process.sleep(100)
      {:ok, instance} = apply(elem(storage, 0), :get, [elem(storage, 1), instance_id])
      assert instance.status == :completed
    end
  end

  describe "dynamic transit/3 workflow end-to-end" do
    test "routes dynamically based on context", %{opts: opts, storage: storage} do
      # Arrange & Act
      {:ok, instance_id} = Hephaestus.Runtime.Runner.Local.start_instance(
        Hephaestus.Test.V2.DynamicWorkflow,
        %{use_b: true},
        opts
      )

      # Assert
      Process.sleep(100)
      {:ok, instance} = apply(elem(storage, 0), :get, [elem(storage, 1), instance_id])
      assert instance.status == :completed
      assert MapSet.member?(instance.completed_steps, Hephaestus.Test.V2.StepB)
      refute MapSet.member?(instance.completed_steps, Hephaestus.Test.V2.StepC)
    end
  end

  describe "context propagation" do
    test "step results accessible via snake_case keys", %{opts: opts, storage: storage} do
      # Arrange & Act
      {:ok, instance_id} = Hephaestus.Runtime.Runner.Local.start_instance(
        Hephaestus.Test.V2.LinearWorkflow,
        %{data: "test"},
        opts
      )

      # Assert
      Process.sleep(100)
      {:ok, instance} = apply(elem(storage, 0), :get, [elem(storage, 1), instance_id])
      assert instance.status == :completed

      # Context keys are snake_case atoms derived from module last segment
      # StepB = PassWithContextStep -> :pass_with_context_step
      assert instance.context.steps[:pass_with_context_step] == %{processed: true}
    end
  end

  describe "crash recovery" do
    test "recovered instance resumes from persisted state", %{opts: opts, storage: storage} do
      # Arrange — start async workflow, it pauses at async step
      {:ok, instance_id} = Hephaestus.Runtime.Runner.Local.start_instance(
        Hephaestus.Test.V2.AsyncWorkflow,
        %{},
        opts
      )

      Process.sleep(100)
      {:ok, instance} = apply(elem(storage, 0), :get, [elem(storage, 1), instance_id])
      assert instance.status == :waiting

      # Act — kill the runner GenServer (simulate crash)
      [{pid, _}] = Registry.lookup(opts[:registry], instance_id)
      Process.exit(pid, :kill)
      Process.sleep(50)

      # Restart via DynamicSupervisor
      child_spec = %{
        id: {Hephaestus.Runtime.Runner.Local, instance_id},
        start: {Hephaestus.Runtime.Runner.Local, :start_link, [[
          instance: instance,
          instance_id: instance_id,
          registry: opts[:registry],
          storage: opts[:storage],
          task_supervisor: opts[:task_supervisor]
        ]]},
        restart: :transient
      }
      {:ok, _pid} = DynamicSupervisor.start_child(opts[:dynamic_supervisor], child_spec)
      Process.sleep(50)

      # Assert — instance still waiting (recovered from storage)
      {:ok, recovered} = apply(elem(storage, 0), :get, [elem(storage, 1), instance_id])
      assert recovered.status == :waiting

      # Resume and complete
      :ok = Hephaestus.Runtime.Runner.Local.resume(instance_id, :timeout)
      Process.sleep(100)
      {:ok, final} = apply(elem(storage, 0), :get, [elem(storage, 1), instance_id])
      assert final.status == :completed
    end
  end
end
```

## Sequencia TDD

1. RED: "start_instance executes to completion" — falha se runtime nao esta integrado com nova API
2. GREEN: ajustar Runner.Local ate linear flow completar
3. RED: testes de branch, fan-out — devem passar se engine esta correto
4. RED: "pauses at async step and resumes with atom event" — valida que resume aceita atom
5. RED: "waits for event and resumes" — valida WaitForEvent com nova API
6. RED: "routes dynamically based on context" — valida transit/3 no runtime
7. RED: "step results accessible via snake_case keys" — valida context propagation end-to-end
8. RED: "crash recovery" — valida recuperacao de estado
