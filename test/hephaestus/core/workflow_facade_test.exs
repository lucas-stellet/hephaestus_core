defmodule Hephaestus.Core.WorkflowFacadeTest do
  use ExUnit.Case, async: false

  alias Hephaestus.Runtime.Storage.ETS, as: ETSStorage

  defmodule TestFacadeWorkflow do
    use Hephaestus.Workflow, unique: [key: "facadestd"]

    @impl true
    def start, do: Hephaestus.Test.V2.StepA

    @impl true
    def transit(Hephaestus.Test.V2.StepA, :done, _ctx), do: Hephaestus.Test.V2.StepB
    def transit(Hephaestus.Test.V2.StepB, :done, _ctx), do: Hephaestus.Steps.Done
  end

  defmodule TestFacadeEventWorkflow do
    use Hephaestus.Workflow, unique: [key: "facadeevent"]

    @impl true
    def start, do: Hephaestus.Test.V2.StepA

    @impl true
    def transit(Hephaestus.Test.V2.StepA, :done, _ctx), do: Hephaestus.Test.V2.WaitForEvent
    def transit(Hephaestus.Test.V2.WaitForEvent, :received, _ctx), do: Hephaestus.Test.V2.StepB
    def transit(Hephaestus.Test.V2.StepB, :done, _ctx), do: Hephaestus.Steps.Done
  end

  defmodule TestFacadeNoneWorkflow do
    use Hephaestus.Workflow, unique: [key: "facadenone", scope: :none]

    @impl true
    def start, do: Hephaestus.Test.V2.StepA

    @impl true
    def transit(Hephaestus.Test.V2.StepA, :done, _ctx), do: Hephaestus.Test.V2.StepB
    def transit(Hephaestus.Test.V2.StepB, :done, _ctx), do: Hephaestus.Steps.Done
  end

  defmodule TestFacadeUmbrella.V1 do
    use Hephaestus.Workflow, version: 1, unique: [key: "facadeumb"]

    @impl true
    def start, do: Hephaestus.Test.V2.StepA

    @impl true
    def transit(Hephaestus.Test.V2.StepA, :done, _ctx), do: Hephaestus.Steps.Done
  end

  defmodule TestFacadeUmbrella.V2 do
    use Hephaestus.Workflow, version: 2, unique: [key: "facadeumb"]

    @impl true
    def start, do: Hephaestus.Test.V2.StepA

    @impl true
    def transit(Hephaestus.Test.V2.StepA, :done, _ctx), do: Hephaestus.Test.V2.StepB
    def transit(Hephaestus.Test.V2.StepB, :done, _ctx), do: Hephaestus.Steps.Done
  end

  defmodule TestFacadeUmbrella do
    use Hephaestus.Workflow,
      versions: %{1 => __MODULE__.V1, 2 => __MODULE__.V2},
      current: 2,
      unique: [key: "facadeumb"]
  end

  setup do
    start_supervised!(Hephaestus.Test.Hephaestus)
    :ok
  end

  describe "start/2" do
    test "creates instance with composite ID for standalone workflows" do
      # Arrange

      # Act
      {:ok, id} = TestFacadeWorkflow.start("abc123", %{source: :test})

      # Assert
      assert id == "facadestd::abc123"
    end

    test "rejects duplicates for standalone workflows" do
      # Arrange
      assert {:ok, "facadestd::dup1"} = TestFacadeWorkflow.start("dup1", %{})

      # Act
      result = TestFacadeWorkflow.start("dup1", %{})

      # Assert
      assert result == {:error, :already_running}
    end

    test "uses the current version for umbrella workflows" do
      # Arrange

      # Act
      {:ok, id} = TestFacadeUmbrella.start("v2value", %{source: :umbrella})

      # Assert
      assert id == "facadeumb::v2value"
      assert {:ok, instance} = get_instance(id)
      assert instance.workflow == TestFacadeUmbrella.V2
      assert instance.workflow_version == 2
    end
  end

  describe "resume/2" do
    test "resumes a waiting workflow by business value" do
      # Arrange
      {:ok, id} = TestFacadeEventWorkflow.start("resume1", %{})
      Process.sleep(100)

      # Act
      result = TestFacadeEventWorkflow.resume("resume1", :received)
      Process.sleep(100)

      # Assert
      assert result == :ok
      assert {:ok, instance} = get_instance(id)
      assert instance.status == :completed
    end
  end

  describe "get/1" do
    test "returns the instance for a standalone workflow" do
      # Arrange
      {:ok, _id} = TestFacadeWorkflow.start("get1", %{data: 42})

      # Act
      result = TestFacadeWorkflow.get("get1")

      # Assert
      assert {:ok, instance} = result
      assert instance.id == "facadestd::get1"
      assert instance.context.initial == %{data: 42}
    end
  end

  describe "list/0 and list/1" do
    test "returns only standalone instances for the workflow" do
      # Arrange
      {:ok, _id1} = TestFacadeWorkflow.start("list1", %{})
      {:ok, _id2} = TestFacadeWorkflow.start("list2", %{})
      {:ok, _other} = TestFacadeEventWorkflow.start("other1", %{})

      # Act
      ids = TestFacadeWorkflow.list() |> Enum.map(& &1.id)

      # Assert
      assert Enum.sort(ids) == ["facadestd::list1", "facadestd::list2"]
    end

    test "accepts additional filters" do
      # Arrange
      {:ok, _id} = TestFacadeEventWorkflow.start("waiting1", %{})
      Process.sleep(100)

      # Act
      result = TestFacadeEventWorkflow.list(status: :waiting)

      # Assert
      assert Enum.all?(result, &(&1.status == :waiting))
      assert Enum.map(result, & &1.id) == ["facadeevent::waiting1"]
    end

    test "returns umbrella workflow instances" do
      # Arrange
      {:ok, _id} = TestFacadeUmbrella.start("listumb1", %{})

      # Act
      ids = TestFacadeUmbrella.list() |> Enum.map(& &1.id)

      # Assert
      assert ids == ["facadeumb::listumb1"]
    end
  end

  describe "cancel/1" do
    test "cancels an active workflow" do
      # Arrange
      {:ok, _id} = TestFacadeEventWorkflow.start("cancel1", %{})
      Process.sleep(100)

      # Act
      result = TestFacadeEventWorkflow.cancel("cancel1")

      # Assert
      assert result == :ok
      assert {:ok, instance} = TestFacadeEventWorkflow.get("cancel1")
      assert instance.status == :cancelled
    end

    test "returns not_cancellable for completed workflows" do
      # Arrange
      {:ok, _id} = TestFacadeWorkflow.start("done1", %{})
      Process.sleep(100)

      # Act
      result = TestFacadeWorkflow.cancel("done1")

      # Assert
      assert result == {:error, :not_cancellable}
    end
  end

  describe "scope :none" do
    test "start/2 creates a suffixed ID" do
      # Arrange

      # Act
      {:ok, id} = TestFacadeNoneWorkflow.start("abc123", %{})

      # Assert
      assert String.starts_with?(id, "facadenone::abc123::")
    end

    test "only start and list are exported" do
      # Arrange

      # Act

      # Assert
      assert function_exported?(TestFacadeNoneWorkflow, :start, 2)
      assert function_exported?(TestFacadeNoneWorkflow, :list, 0)
      assert function_exported?(TestFacadeNoneWorkflow, :list, 1)
      refute function_exported?(TestFacadeNoneWorkflow, :resume, 2)
      refute function_exported?(TestFacadeNoneWorkflow, :get, 1)
      refute function_exported?(TestFacadeNoneWorkflow, :cancel, 1)
    end
  end

  defp get_instance(id) do
    ETSStorage.get(Hephaestus.Test.Hephaestus.Storage, id)
  end
end
