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
  end

  describe "start_instance/3 - parallel workflow (fan-out/fan-in)" do
    test "executes parallel branches and joins", %{opts: opts, storage: storage} do
      {:ok, id} = RunnerLocal.start_instance(Hephaestus.Test.ParallelWorkflow, %{}, opts)

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
end
