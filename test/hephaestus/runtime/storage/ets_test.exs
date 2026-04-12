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

  defp new_instance(workflow, context \\ %{}) do
    Instance.new(workflow, 1, context, "ets-test-#{System.unique_integer([:positive])}")
  end

  describe "put/1 and get/1" do
    test "stores and retrieves instance", %{storage: storage} do
      instance = new_instance(TestWorkflow, %{order_id: 123})

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
      instance = new_instance(TestWorkflow)
      :ok = ETSStorage.put(storage, instance)

      updated = %{instance | status: :completed}
      :ok = ETSStorage.put(storage, updated)

      {:ok, retrieved} = ETSStorage.get(storage, instance.id)

      assert retrieved.status == :completed
    end
  end

  describe "delete/1" do
    test "removes instance from storage", %{storage: storage} do
      instance = new_instance(TestWorkflow)
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
      instance_a = new_instance(TestWorkflow)
      instance_b = new_instance(TestWorkflow)
      :ok = ETSStorage.put(storage, instance_a)
      :ok = ETSStorage.put(storage, instance_b)

      results = ETSStorage.query(storage, [])

      assert length(results) == 2
    end

    test "filters by status", %{storage: storage} do
      pending = new_instance(TestWorkflow)
      completed = %{new_instance(TestWorkflow) | status: :completed}
      :ok = ETSStorage.put(storage, pending)
      :ok = ETSStorage.put(storage, completed)

      results = ETSStorage.query(storage, status: :completed)

      assert length(results) == 1
      assert hd(results).status == :completed
    end

    test "filters by workflow", %{storage: storage} do
      instance_a = new_instance(WorkflowA)
      instance_b = new_instance(WorkflowB)
      :ok = ETSStorage.put(storage, instance_a)
      :ok = ETSStorage.put(storage, instance_b)

      results = ETSStorage.query(storage, workflow: WorkflowA)

      assert length(results) == 1
      assert hd(results).workflow == WorkflowA
    end

    test "returns empty list when no matches", %{storage: storage} do
      instance = new_instance(TestWorkflow)
      :ok = ETSStorage.put(storage, instance)

      results = ETSStorage.query(storage, status: :completed)

      assert results == []
    end
  end

  describe "concurrent access" do
    test "stores every instance written by parallel puts", %{storage: storage} do
      instances = for index <- 1..48, do: new_instance(TestWorkflow, %{index: index})

      results =
        Task.async_stream(
          instances,
          fn instance ->
            :ok = ETSStorage.put(storage, instance)
            instance.id
          end,
          ordered: false,
          max_concurrency: 12,
          timeout: 5_000
        )
        |> Enum.to_list()

      assert Enum.sort(Enum.map(results, fn {:ok, id} -> id end)) ==
               Enum.sort(Enum.map(instances, & &1.id))

      stored_ids =
        storage
        |> ETSStorage.query([])
        |> Enum.map(& &1.id)
        |> Enum.sort()

      assert stored_ids == Enum.sort(Enum.map(instances, & &1.id))
    end

    test "returns only not_found or the final persisted instance during concurrent get and put",
         %{
           storage: storage
         } do
      instances = for index <- 1..24, do: new_instance(TestWorkflow, %{index: index})
      ids = MapSet.new(Enum.map(instances, & &1.id))

      writer =
        Task.async(fn ->
          Enum.each(instances, fn instance ->
            :ok = ETSStorage.put(storage, instance)
            Process.sleep(2)
          end)
        end)

      reader_results =
        Task.async_stream(
          1..80,
          fn _attempt ->
            Enum.map(instances, fn instance ->
              case ETSStorage.get(storage, instance.id) do
                {:ok, retrieved} -> {:ok, retrieved.id, retrieved.context.initial[:index]}
                {:error, :not_found} -> :not_found
              end
            end)
          end,
          ordered: false,
          max_concurrency: 8,
          timeout: 5_000
        )
        |> Enum.flat_map(fn {:ok, batch} -> batch end)

      assert Task.await(writer, 5_000) == :ok

      assert Enum.all?(reader_results, fn
               :not_found ->
                 true

               {:ok, id, index} ->
                 MapSet.member?(ids, id) and is_integer(index)
             end)

      Enum.each(instances, fn instance ->
        assert {:ok, retrieved} = ETSStorage.get(storage, instance.id)
        assert retrieved.context.initial == instance.context.initial
      end)
    end

    test "queries converge to the full set while writes are in flight", %{storage: storage} do
      pending_instances =
        for index <- 1..12, do: new_instance(TestWorkflow, %{kind: :pending, index: index})

      completed_instances =
        for index <- 1..12 do
          %{new_instance(TestWorkflow, %{kind: :completed, index: index}) | status: :completed}
        end

      all_instances = pending_instances ++ completed_instances

      writer =
        Task.async(fn ->
          Enum.each(all_instances, fn instance ->
            :ok = ETSStorage.put(storage, instance)
            Process.sleep(2)
          end)
        end)

      observed_counts =
        Task.async_stream(
          1..60,
          fn _attempt ->
            %{
              all: length(ETSStorage.query(storage, [])),
              completed: length(ETSStorage.query(storage, status: :completed))
            }
          end,
          ordered: false,
          max_concurrency: 6,
          timeout: 5_000
        )
        |> Enum.map(fn {:ok, counts} -> counts end)

      assert Task.await(writer, 5_000) == :ok

      assert Enum.all?(observed_counts, fn %{all: all, completed: completed} ->
               all >= completed and all <= length(all_instances) and
                 completed <= length(completed_instances)
             end)

      assert length(ETSStorage.query(storage, [])) == length(all_instances)
      assert length(ETSStorage.query(storage, status: :completed)) == length(completed_instances)
    end
  end
end
