defmodule Hephaestus.Runtime.Runner.LocalV2Test do
  use ExUnit.Case, async: false

  alias Hephaestus.Runtime.Runner.Local, as: RunnerLocal
  alias Hephaestus.Runtime.Storage.ETS, as: ETSStorage

  setup do
    name = :"test_heph_v2_#{System.unique_integer([:positive])}"

    registry = Module.concat(name, Registry)
    dynamic_supervisor = Module.concat(name, DynamicSupervisor)
    task_supervisor = Module.concat(name, TaskSupervisor)
    storage_name = Module.concat(name, Storage)

    children = [
      {Registry, keys: :unique, name: registry},
      {DynamicSupervisor, name: dynamic_supervisor, strategy: :one_for_one},
      {Task.Supervisor, name: task_supervisor},
      {ETSStorage, name: storage_name}
    ]

    {:ok, _sup} = Supervisor.start_link(children, strategy: :one_for_one)

    opts = [
      storage: {ETSStorage, storage_name},
      registry: registry,
      dynamic_supervisor: dynamic_supervisor,
      task_supervisor: task_supervisor
    ]

    %{opts: opts, storage: storage_name}
  end

  describe "linear workflow end-to-end" do
    test "start_instance executes to completion", %{opts: opts, storage: storage} do
      opts = put_instance_id(opts, "test-v2-linear")

      assert {:ok, instance_id} =
               RunnerLocal.start_instance(Hephaestus.Test.V2.LinearWorkflow, %{data: "test"}, opts)

      instance = wait_for_instance(storage, instance_id, &(&1.status == :completed))

      assert MapSet.member?(instance.completed_steps, Hephaestus.Test.V2.StepA)
      assert MapSet.member?(instance.completed_steps, Hephaestus.Test.V2.StepB)
      assert MapSet.member?(instance.completed_steps, Hephaestus.Steps.Done)
    end
  end

  describe "branch workflow end-to-end" do
    test "follows approved branch to completion", %{opts: opts, storage: storage} do
      opts = put_instance_id(opts, "test-v2-branch-approve")

      assert {:ok, instance_id} =
               RunnerLocal.start_instance(
                 Hephaestus.Test.V2.BranchWorkflow,
                 %{should_approve: true},
                 opts
               )

      instance = wait_for_instance(storage, instance_id, &(&1.status == :completed))

      assert MapSet.member?(instance.completed_steps, Hephaestus.Test.V2.ApproveStep)
      refute MapSet.member?(instance.completed_steps, Hephaestus.Test.V2.RejectStep)
    end

    test "follows rejected branch to completion", %{opts: opts, storage: storage} do
      opts = put_instance_id(opts, "test-v2-branch-reject")

      assert {:ok, instance_id} =
               RunnerLocal.start_instance(
                 Hephaestus.Test.V2.BranchWorkflow,
                 %{should_approve: false},
                 opts
               )

      instance = wait_for_instance(storage, instance_id, &(&1.status == :completed))

      assert MapSet.member?(instance.completed_steps, Hephaestus.Test.V2.RejectStep)
      refute MapSet.member?(instance.completed_steps, Hephaestus.Test.V2.ApproveStep)
    end
  end

  describe "fan-out workflow end-to-end" do
    test "parallel steps execute and converge at join", %{opts: opts, storage: storage} do
      opts = put_instance_id(opts, "test-v2-fanout")

      assert {:ok, instance_id} =
               RunnerLocal.start_instance(Hephaestus.Test.V2.FanOutWorkflow, %{}, opts)

      instance = wait_for_instance(storage, instance_id, &(&1.status == :completed), 1_500)

      assert MapSet.member?(instance.completed_steps, Hephaestus.Test.V2.ParallelA)
      assert MapSet.member?(instance.completed_steps, Hephaestus.Test.V2.ParallelB)
      assert MapSet.member?(instance.completed_steps, Hephaestus.Test.V2.JoinStep)
    end
  end

  describe "async workflow with resume" do
    test "pauses at async step and resumes with atom event", %{opts: opts, storage: storage} do
      opts = put_instance_id(opts, "test-v2-async")

      assert {:ok, instance_id} =
               RunnerLocal.start_instance(Hephaestus.Test.V2.AsyncWorkflow, %{}, opts)

      waiting = wait_for_instance(storage, instance_id, &(&1.status == :waiting))
      assert waiting.current_step == Hephaestus.Test.V2.AsyncWait

      assert :ok = RunnerLocal.resume(instance_id, :timeout)

      instance = wait_for_instance(storage, instance_id, &(&1.status == :completed))
      assert MapSet.member?(instance.completed_steps, Hephaestus.Test.V2.AsyncWait)
      assert instance.current_step == nil
    end
  end

  describe "event workflow with external resume" do
    test "waits for event and resumes on external trigger", %{opts: opts, storage: storage} do
      opts = put_instance_id(opts, "test-v2-event")

      assert {:ok, instance_id} =
               RunnerLocal.start_instance(Hephaestus.Test.V2.EventWorkflow, %{}, opts)

      waiting = wait_for_instance(storage, instance_id, &(&1.status == :waiting))
      assert waiting.current_step == Hephaestus.Test.V2.WaitForEvent

      assert :ok = RunnerLocal.resume(instance_id, :received)

      instance = wait_for_instance(storage, instance_id, &(&1.status == :completed))
      assert MapSet.member?(instance.completed_steps, Hephaestus.Test.V2.WaitForEvent)
      assert instance.current_step == nil
    end
  end

  describe "dynamic transit/3 workflow end-to-end" do
    test "routes dynamically based on context", %{opts: opts, storage: storage} do
      opts = put_instance_id(opts, "test-v2-dynamic")

      assert {:ok, instance_id} =
               RunnerLocal.start_instance(Hephaestus.Test.V2.DynamicWorkflow, %{use_b: true}, opts)

      instance = wait_for_instance(storage, instance_id, &(&1.status == :completed))

      assert MapSet.member?(instance.completed_steps, Hephaestus.Test.V2.StepB)
      refute MapSet.member?(instance.completed_steps, Hephaestus.Test.V2.StepC)
    end
  end

  describe "context propagation" do
    test "step results accessible via snake_case keys", %{opts: opts, storage: storage} do
      opts = put_instance_id(opts, "test-v2-context")

      assert {:ok, instance_id} =
               RunnerLocal.start_instance(Hephaestus.Test.V2.LinearWorkflow, %{data: "test"}, opts)

      instance = wait_for_instance(storage, instance_id, &(&1.status == :completed))

      assert instance.context.steps[:step_b] == %{processed: true}
    end
  end

  describe "crash recovery" do
    test "recovered instance resumes from persisted state", %{opts: opts, storage: storage} do
      opts = put_instance_id(opts, "test-v2-crash")

      assert {:ok, instance_id} =
               RunnerLocal.start_instance(Hephaestus.Test.V2.AsyncWorkflow, %{}, opts)

      waiting = wait_for_instance(storage, instance_id, &(&1.status == :waiting))
      assert waiting.completed_steps == MapSet.new([Hephaestus.Test.V2.StepA])

      registry = opts[:registry]
      assert [{old_pid, _}] = Registry.lookup(registry, instance_id)

      Process.exit(old_pid, :kill)

      wait_until(fn ->
        case Registry.lookup(registry, instance_id) do
          [{new_pid, _}] when new_pid != old_pid -> Process.alive?(new_pid)
          _ -> false
        end
      end)

      resumed_waiting = wait_for_instance(storage, instance_id, &(&1.status == :waiting))
      assert resumed_waiting.completed_steps == waiting.completed_steps

      assert :ok = RunnerLocal.resume(instance_id, :timeout)

      instance = wait_for_instance(storage, instance_id, &(&1.status == :completed))
      assert MapSet.member?(instance.completed_steps, Hephaestus.Test.V2.AsyncWait)
      assert MapSet.member?(instance.completed_steps, Hephaestus.Test.V2.StepB)
      assert instance.current_step == nil
    end
  end

  defp wait_for_instance(storage, id, predicate, timeout \\ 1_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_for_instance(storage, id, predicate, deadline)
  end

  defp do_wait_for_instance(storage, id, predicate, deadline) do
    case ETSStorage.get(storage, id) do
      {:ok, instance} ->
        if predicate.(instance) do
          instance
        else
          retry_wait(storage, id, predicate, deadline)
        end

      {:error, :not_found} ->
        retry_wait(storage, id, predicate, deadline)
    end
  end

  defp retry_wait(storage, id, predicate, deadline) do
    if System.monotonic_time(:millisecond) < deadline do
      Process.sleep(10)
      do_wait_for_instance(storage, id, predicate, deadline)
    else
      flunk("timed out waiting for instance #{id}")
    end
  end

  defp wait_until(fun, timeout \\ 1_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_until(fun, deadline)
  end

  defp do_wait_until(fun, deadline) do
    if fun.() do
      :ok
    else
      if System.monotonic_time(:millisecond) < deadline do
        Process.sleep(10)
        do_wait_until(fun, deadline)
      else
        flunk("timed out waiting for condition")
      end
    end
  end

  defp put_instance_id(opts, id), do: Keyword.put(opts, :id, id)
end
