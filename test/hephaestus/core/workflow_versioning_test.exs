defmodule Hephaestus.Core.WorkflowVersioningTest do
  use ExUnit.Case, async: true

  defmodule ExplicitV3Flow do
    use Hephaestus.Workflow, version: 3

    def start, do: Hephaestus.Test.V2.StepA
    def transit(Hephaestus.Test.V2.StepA, :done, _ctx), do: Hephaestus.Steps.Done
  end

  describe "implicit version (no version: option)" do
    test "existing workflow has __version__/0 = 1" do
      # Assert — uses pre-existing test fixture
      assert Hephaestus.Test.V2.LinearWorkflow.__version__() == 1
    end

    test "existing workflow has __versioned__?/0 = false" do
      # Assert
      assert Hephaestus.Test.V2.LinearWorkflow.__versioned__?() == false
    end

    test "resolve_version(nil) returns {1, module}" do
      # Act
      result = Hephaestus.Test.V2.LinearWorkflow.resolve_version(nil)

      # Assert
      assert result == {1, Hephaestus.Test.V2.LinearWorkflow}
    end

    test "resolve_version(1) returns {1, module}" do
      # Act
      result = Hephaestus.Test.V2.LinearWorkflow.resolve_version(1)

      # Assert
      assert result == {1, Hephaestus.Test.V2.LinearWorkflow}
    end

    test "resolve_version(2) raises ArgumentError" do
      # Assert
      assert_raise ArgumentError, ~r/not a versioned workflow/, fn ->
        Hephaestus.Test.V2.LinearWorkflow.resolve_version(2)
      end
    end
  end

  describe "explicit version" do
    test "workflow with version: 3 has __version__/0 = 3" do
      # Assert
      assert ExplicitV3Flow.__version__() == 3
      assert ExplicitV3Flow.__versioned__?() == false
    end

    test "resolve_version matches explicit version" do
      # Act & Assert
      assert ExplicitV3Flow.resolve_version(nil) == {3, ExplicitV3Flow}
      assert ExplicitV3Flow.resolve_version(3) == {3, ExplicitV3Flow}
    end

    test "resolve_version raises for non-matching version" do
      # Assert
      assert_raise ArgumentError, fn ->
        ExplicitV3Flow.resolve_version(1)
      end
    end
  end
end
