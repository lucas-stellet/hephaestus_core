defmodule Hephaestus.EntryModuleTest do
  use ExUnit.Case, async: false

  alias Hephaestus.Runtime.Storage.ETS, as: ETSStorage

  defmodule TestHephaestus do
    use Hephaestus,
      storage: Hephaestus.Runtime.Storage.ETS,
      runner: Hephaestus.Runtime.Runner.Local
  end

  setup do
    {:ok, pid} = start_supervised(TestHephaestus)
    %{sup: pid}
  end

  describe "supervision tree" do
    test "starts all child processes" do
      assert Process.whereis(TestHephaestus.Registry) != nil
      assert Process.whereis(TestHephaestus.DynamicSupervisor) != nil
      assert Process.whereis(TestHephaestus.TaskSupervisor) != nil
      assert Process.whereis(TestHephaestus.Storage) != nil
    end
  end

  describe "start_instance/2" do
    test "starts a workflow and returns instance id" do
      assert {:ok, instance_id} =
               TestHephaestus.start_instance(Hephaestus.Test.LinearWorkflow, %{order_id: 123})

      assert is_binary(instance_id)
    end

    test "workflow completes end-to-end" do
      assert {:ok, instance_id} =
               TestHephaestus.start_instance(Hephaestus.Test.LinearWorkflow, %{})

      Process.sleep(100)

      assert {:ok, instance} = ETSStorage.get(TestHephaestus.Storage, instance_id)
      assert instance.status == :completed
    end
  end

  describe "resume/2" do
    test "resumes async workflow" do
      assert {:ok, id} = TestHephaestus.start_instance(Hephaestus.Test.AsyncWorkflow, %{})
      Process.sleep(100)

      assert :ok = TestHephaestus.resume(id, "timeout")
      Process.sleep(100)

      assert {:ok, instance} = ETSStorage.get(TestHephaestus.Storage, id)
      assert instance.status == :completed
    end
  end

  describe "parallel workflow end-to-end" do
    test "fan-out/fan-in completes via entry module" do
      assert {:ok, id} = TestHephaestus.start_instance(Hephaestus.Test.ParallelWorkflow, %{})
      Process.sleep(200)

      assert {:ok, instance} = ETSStorage.get(TestHephaestus.Storage, id)
      assert instance.status == :completed
      assert MapSet.member?(instance.completed_steps, :join)
    end
  end
end
