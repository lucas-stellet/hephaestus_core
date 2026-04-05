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

  describe "start_instance/3 - linear workflow" do
    test "starts and completes a sync workflow", %{opts: opts, storage: storage} do
      {:ok, instance_id} = RunnerLocal.start_instance(Hephaestus.Test.LinearWorkflow, %{}, opts)

      Process.sleep(100)
      {:ok, instance} = ETSStorage.get(storage, instance_id)
      assert instance.status == :completed
    end

    test "persists instance in storage", %{opts: opts, storage: storage} do
      {:ok, instance_id} = RunnerLocal.start_instance(Hephaestus.Test.LinearWorkflow, %{}, opts)

      Process.sleep(100)
      assert {:ok, _instance} = ETSStorage.get(storage, instance_id)
    end
  end

  describe "start_instance/3 - branching workflow" do
    test "follows correct branch based on context", %{opts: opts, storage: storage} do
      {:ok, id} =
        RunnerLocal.start_instance(
          Hephaestus.Test.BranchWorkflow,
          %{should_approve: true},
          opts
        )

      Process.sleep(100)
      {:ok, instance} = ETSStorage.get(storage, id)
      assert instance.status == :completed
      assert MapSet.member?(instance.completed_steps, :approve)
    end
  end

  describe "start_instance/3 - async workflow" do
    test "pauses at async step", %{opts: opts, storage: storage} do
      {:ok, id} = RunnerLocal.start_instance(Hephaestus.Test.AsyncWorkflow, %{}, opts)

      Process.sleep(100)
      {:ok, instance} = ETSStorage.get(storage, id)
      assert instance.status == :waiting
    end
  end

  describe "start_instance/3 - event workflow" do
    test "pauses at wait_for_event", %{opts: opts, storage: storage} do
      {:ok, id} = RunnerLocal.start_instance(Hephaestus.Test.EventWorkflow, %{}, opts)

      Process.sleep(100)
      {:ok, instance} = ETSStorage.get(storage, id)

      assert instance.status == :waiting
      assert instance.current_step == :wait_for_event
      assert instance.active_steps == MapSet.new([:wait_for_event])
    end

    test "resumes with payment_confirmed and completes", %{opts: opts, storage: storage} do
      {:ok, id} = RunnerLocal.start_instance(Hephaestus.Test.EventWorkflow, %{}, opts)
      Process.sleep(100)

      :ok = RunnerLocal.resume(id, "payment_confirmed")
      Process.sleep(100)

      {:ok, instance} = ETSStorage.get(storage, id)
      assert instance.status == :completed
    end

    test "records all completed steps", %{opts: opts, storage: storage} do
      {:ok, id} = RunnerLocal.start_instance(Hephaestus.Test.EventWorkflow, %{}, opts)
      Process.sleep(100)

      :ok = RunnerLocal.resume(id, "payment_confirmed")
      Process.sleep(100)

      {:ok, instance} = ETSStorage.get(storage, id)

      assert MapSet.subset?(
               MapSet.new([:step_a, :wait_for_event, :step_b, :finish]),
               instance.completed_steps
             )
    end

    test "stores context updates from step_b", %{opts: opts, storage: storage} do
      {:ok, id} = RunnerLocal.start_instance(Hephaestus.Test.EventWorkflow, %{}, opts)
      Process.sleep(100)

      :ok = RunnerLocal.resume(id, "payment_confirmed")
      Process.sleep(100)

      {:ok, instance} = ETSStorage.get(storage, id)
      assert %{processed: true} = instance.context.steps[:step_b]
    end
  end

  describe "resume/2" do
    test "resumes paused instance and completes", %{opts: opts, storage: storage} do
      {:ok, id} = RunnerLocal.start_instance(Hephaestus.Test.AsyncWorkflow, %{}, opts)
      Process.sleep(100)

      :ok = RunnerLocal.resume(id, "timeout")
      Process.sleep(100)

      {:ok, instance} = ETSStorage.get(storage, id)
      assert instance.status == :completed
    end

    test "returns error for nonexistent instance" do
      assert {:error, :instance_not_found} = RunnerLocal.resume("nonexistent", "event")
    end

    test "returns error when the instance has already completed", %{opts: opts, storage: storage} do
      {:ok, id} = RunnerLocal.start_instance(Hephaestus.Test.LinearWorkflow, %{}, opts)

      instance = wait_for_instance(storage, id, &(&1.status == :completed))
      assert instance.active_steps == MapSet.new()

      assert {:error, :instance_not_found} = RunnerLocal.resume(id, "timeout")
    end
  end

  describe "schedule_resume/3" do
    test "resumes instance after delay", %{opts: opts, storage: storage} do
      {:ok, id} = RunnerLocal.start_instance(Hephaestus.Test.AsyncWorkflow, %{}, opts)
      Process.sleep(100)

      {:ok, _ref} = RunnerLocal.schedule_resume(id, :wait, 50)
      Process.sleep(200)

      {:ok, instance} = ETSStorage.get(storage, id)
      assert instance.status == :completed
    end

    test "returns error for nonexistent instance" do
      assert {:error, :instance_not_found} = RunnerLocal.schedule_resume("nonexistent", :wait, 50)
    end
  end

  describe "start_instance/3 - parallel workflow (fan-out/fan-in)" do
    test "executes parallel branches and joins", %{opts: opts, storage: storage} do
      {:ok, id} = RunnerLocal.start_instance(Hephaestus.Test.ParallelWorkflow, %{}, opts)

      Process.sleep(200)
      {:ok, instance} = ETSStorage.get(storage, id)
      assert instance.status == :completed
      assert MapSet.member?(instance.completed_steps, :branch_a)
      assert MapSet.member?(instance.completed_steps, :branch_b)
      assert MapSet.member?(instance.completed_steps, :branch_c)
      assert MapSet.member?(instance.completed_steps, :join)
    end
  end

  describe "runtime state assertions" do
    test "persists completed_steps, active_steps, and step context after an event resume", %{
      opts: opts,
      storage: storage
    } do
      {:ok, id} = RunnerLocal.start_instance(Hephaestus.Test.EventWorkflow, %{}, opts)

      waiting = wait_for_instance(storage, id, &(&1.status == :waiting))
      assert waiting.current_step == :wait_for_event
      assert waiting.active_steps == MapSet.new([:wait_for_event])

      :ok = RunnerLocal.resume(id, "payment_confirmed")

      completed = wait_for_instance(storage, id, &(&1.status == :completed))

      assert completed.current_step == nil
      assert completed.active_steps == MapSet.new()

      assert MapSet.subset?(
               MapSet.new([:step_a, :wait_for_event, :step_b, :finish]),
               completed.completed_steps
             )

      assert completed.context.steps == %{
               step_a: %{},
               wait_for_event: %{},
               step_b: %{processed: true},
               finish: %{}
             }
      assert completed.execution_history == []
    end

    test "persists every parallel branch result before the join completes", %{
      opts: opts,
      storage: storage
    } do
      {:ok, id} = RunnerLocal.start_instance(Hephaestus.Test.ParallelWorkflow, %{}, opts)

      completed = wait_for_instance(storage, id, &(&1.status == :completed), 1_500)

      assert completed.current_step == nil
      assert completed.active_steps == MapSet.new()

      assert MapSet.subset?(
               MapSet.new([:start, :branch_a, :branch_b, :branch_c, :join, :finish]),
               completed.completed_steps
             )

      assert completed.context.steps == %{
               start: %{},
               branch_a: %{processed: true},
               branch_b: %{processed: true},
               branch_c: %{processed: true},
               join: %{},
               finish: %{}
             }

      assert completed.execution_history == []
    end
  end

  describe "GenServer lifecycle" do
    test "GenServer stops after workflow completes", %{opts: opts} do
      {:ok, id} = RunnerLocal.start_instance(Hephaestus.Test.LinearWorkflow, %{}, opts)
      Process.sleep(100)

      registry = opts[:registry]
      assert Registry.lookup(registry, id) == []
    end

    test "registers in Registry while running", %{opts: opts} do
      {:ok, id} = RunnerLocal.start_instance(Hephaestus.Test.AsyncWorkflow, %{}, opts)
      Process.sleep(100)

      registry = opts[:registry]
      assert [{pid, _}] = Registry.lookup(registry, id)
      assert Process.alive?(pid)
    end
  end

  describe "crash recovery" do
    test "waiting instance survives crash and can resume", %{opts: opts, storage: storage} do
      {:ok, id} = RunnerLocal.start_instance(Hephaestus.Test.AsyncWorkflow, %{}, opts)
      Process.sleep(100)

      registry = opts[:registry]
      assert [{old_pid, _}] = Registry.lookup(registry, id)

      Process.exit(old_pid, :kill)
      Process.sleep(100)

      assert [{new_pid, _}] = Registry.lookup(registry, id)
      refute new_pid == old_pid
      assert Process.alive?(new_pid)

      :ok = RunnerLocal.resume(id, "timeout")
      Process.sleep(100)

      {:ok, instance} = ETSStorage.get(storage, id)
      assert instance.status == :completed
    end

    test "waiting instance keeps persisted state across crash", %{opts: opts, storage: storage} do
      {:ok, id} = RunnerLocal.start_instance(Hephaestus.Test.AsyncWorkflow, %{}, opts)
      Process.sleep(100)

      {:ok, before_crash} = ETSStorage.get(storage, id)
      assert before_crash.status == :waiting
      assert before_crash.completed_steps == MapSet.new([:step_a])

      registry = opts[:registry]
      assert [{pid, _}] = Registry.lookup(registry, id)

      Process.exit(pid, :kill)
      Process.sleep(100)

      {:ok, after_crash} = ETSStorage.get(storage, id)
      assert after_crash.status == :waiting
      assert after_crash.completed_steps == before_crash.completed_steps

      :ok = RunnerLocal.resume(id, "timeout")
      Process.sleep(100)

      {:ok, resumed} = ETSStorage.get(storage, id)
      assert resumed.status == :completed
    end

    test "completed instance is not restarted after normal stop", %{opts: opts} do
      {:ok, id} = RunnerLocal.start_instance(Hephaestus.Test.LinearWorkflow, %{}, opts)
      Process.sleep(100)

      registry = opts[:registry]
      assert Registry.lookup(registry, id) == []

      Process.sleep(100)
      assert Registry.lookup(registry, id) == []
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
end
