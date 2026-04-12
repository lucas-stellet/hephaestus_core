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

    test "Hephaestus module is discoverable via Instances.lookup!" do
      assert Hephaestus.Instances.lookup!() == TestHephaestus
    end
  end

  describe "start_instance/3 with custom ID" do
    test "accepts and passes through explicit ID" do
      assert {:ok, instance_id} =
               TestHephaestus.start_instance(
                 Hephaestus.Test.LinearWorkflow,
                 %{order_id: 123},
                 id: "testlinear::entry1"
               )

      assert instance_id == "testlinear::entry1"
    end

    test "raises KeyError when :id is not provided" do
      assert_raise KeyError, ~r/key :id not found/, fn ->
        TestHephaestus.start_instance(Hephaestus.Test.LinearWorkflow, %{})
      end
    end

    test "workflow completes end-to-end" do
      assert {:ok, instance_id} =
               TestHephaestus.start_instance(
                 Hephaestus.Test.LinearWorkflow,
                 %{},
                 id: "testlinear::entry2"
               )

      Process.sleep(100)

      assert {:ok, instance} = ETSStorage.get(TestHephaestus.Storage, instance_id)
      assert instance.status == :completed
    end
  end

  describe "resume/2" do
    test "resumes async workflow" do
      assert {:ok, id} =
               TestHephaestus.start_instance(
                 Hephaestus.Test.AsyncWorkflow,
                 %{},
                 id: "testasync::entry1"
               )

      Process.sleep(100)

      assert :ok = TestHephaestus.resume(id, :timeout)
      Process.sleep(100)

      assert {:ok, instance} = ETSStorage.get(TestHephaestus.Storage, id)
      assert instance.status == :completed
    end

    test "resumes event workflow with payment_confirmed" do
      assert {:ok, id} =
               TestHephaestus.start_instance(
                 Hephaestus.Test.EventWorkflow,
                 %{},
                 id: "testevent::entry1"
               )

      Process.sleep(100)

      assert {:ok, waiting_instance} = ETSStorage.get(TestHephaestus.Storage, id)
      assert waiting_instance.status == :waiting
      assert waiting_instance.current_step == Hephaestus.Test.Event.WaitForEvent

      assert :ok = TestHephaestus.resume(id, :payment_confirmed)
      Process.sleep(100)

      assert {:ok, instance} = ETSStorage.get(TestHephaestus.Storage, id)
      assert instance.status == :completed
      assert %{processed: true} = instance.context.steps[:step_b]
    end
  end

  describe "parallel workflow end-to-end" do
    test "fan-out/fan-in completes via entry module" do
      assert {:ok, id} =
               TestHephaestus.start_instance(
                 Hephaestus.Test.ParallelWorkflow,
                 %{},
                 id: "testparallel::entry1"
               )

      Process.sleep(200)

      assert {:ok, instance} = ETSStorage.get(TestHephaestus.Storage, id)
      assert instance.status == :completed
      assert MapSet.member?(instance.completed_steps, Hephaestus.Test.Parallel.Join)
    end
  end

  describe "__storage__/0" do
    test "returns the storage adapter tuple" do
      {mod, name} = TestHephaestus.__storage__()

      assert mod == Hephaestus.Runtime.Storage.ETS
      assert name == TestHephaestus.Storage
    end
  end

  describe "tuple config" do
    test "accepts {module, opts} for storage" do
      # Arrange
      assert Code.ensure_loaded?(Hephaestus.Test.TupleConfigHephaestus)

      # Act
      exported = function_exported?(Hephaestus.Test.TupleConfigHephaestus, :child_spec, 1)

      # Assert
      assert exported == true
    end

    test "tuple config starts supervision tree" do
      # Arrange

      # Act
      {:ok, pid} = start_supervised(Hephaestus.Test.TupleConfigHephaestus)

      # Assert
      assert is_pid(pid)
      assert Process.whereis(Hephaestus.Test.TupleConfigHephaestus.Storage) != nil
    end

    test "bare module config still starts supervision tree", %{sup: pid} do
      # Arrange

      # Act

      # Assert
      assert is_pid(pid)
      assert Process.whereis(TestHephaestus.Storage) != nil
    end
  end
end
