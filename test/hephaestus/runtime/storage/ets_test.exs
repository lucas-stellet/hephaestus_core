defmodule Hephaestus.Runtime.Storage.ETSTest do
  use ExUnit.Case, async: false

  alias Hephaestus.Core.Instance
  alias Hephaestus.Runtime.Storage.ETS, as: ETSStorage

  defmodule TestWorkflow do
  end

  defmodule WorkflowA do
  end

  defmodule WorkflowB do
  end

  setup do
    name = :"test_storage_#{System.unique_integer([:positive])}"
    {:ok, pid} = ETSStorage.start_link(name: name)
    %{storage: name, pid: pid}
  end

  describe "put/1 and get/1" do
    test "stores and retrieves instance", %{storage: storage} do
      instance = Instance.new(TestWorkflow, %{order_id: 123})

      :ok = ETSStorage.put(storage, instance)
      result = ETSStorage.get(storage, instance.id)

      assert {:ok, retrieved} = result
      assert retrieved.id == instance.id
      assert retrieved.context.initial == %{order_id: 123}
    end

    test "returns error for nonexistent instance", %{storage: storage} do
      result = ETSStorage.get(storage, "nonexistent")

      assert {:error, :not_found} = result
    end

    test "overwrites existing instance on put", %{storage: storage} do
      instance = Instance.new(TestWorkflow, %{})
      :ok = ETSStorage.put(storage, instance)

      updated = %{instance | status: :completed}
      :ok = ETSStorage.put(storage, updated)

      {:ok, retrieved} = ETSStorage.get(storage, instance.id)

      assert retrieved.status == :completed
    end
  end

  describe "delete/1" do
    test "removes instance from storage", %{storage: storage} do
      instance = Instance.new(TestWorkflow, %{})
      :ok = ETSStorage.put(storage, instance)

      :ok = ETSStorage.delete(storage, instance.id)

      assert {:error, :not_found} = ETSStorage.get(storage, instance.id)
    end

    test "returns ok for nonexistent instance", %{storage: storage} do
      assert :ok = ETSStorage.delete(storage, "nonexistent")
    end
  end

  describe "query/1" do
    test "returns all instances when no filters", %{storage: storage} do
      instance_a = Instance.new(TestWorkflow, %{})
      instance_b = Instance.new(TestWorkflow, %{})
      :ok = ETSStorage.put(storage, instance_a)
      :ok = ETSStorage.put(storage, instance_b)

      results = ETSStorage.query(storage, [])

      assert length(results) == 2
    end

    test "filters by status", %{storage: storage} do
      pending = Instance.new(TestWorkflow, %{})
      completed = %{Instance.new(TestWorkflow, %{}) | status: :completed}
      :ok = ETSStorage.put(storage, pending)
      :ok = ETSStorage.put(storage, completed)

      results = ETSStorage.query(storage, status: :completed)

      assert length(results) == 1
      assert hd(results).status == :completed
    end

    test "filters by workflow", %{storage: storage} do
      instance_a = Instance.new(WorkflowA, %{})
      instance_b = Instance.new(WorkflowB, %{})
      :ok = ETSStorage.put(storage, instance_a)
      :ok = ETSStorage.put(storage, instance_b)

      results = ETSStorage.query(storage, workflow: WorkflowA)

      assert length(results) == 1
      assert hd(results).workflow == WorkflowA
    end

    test "returns empty list when no matches", %{storage: storage} do
      instance = Instance.new(TestWorkflow, %{})
      :ok = ETSStorage.put(storage, instance)

      results = ETSStorage.query(storage, status: :completed)

      assert results == []
    end
  end
end
