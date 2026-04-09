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

  defmodule Umbrella.V1 do
    use Hephaestus.Workflow, version: 1
    def start, do: Hephaestus.Test.V2.StepA
    def transit(Hephaestus.Test.V2.StepA, :done, _ctx), do: Hephaestus.Steps.Done
  end

  defmodule Umbrella.V2 do
    use Hephaestus.Workflow, version: 2
    def start, do: Hephaestus.Test.V2.StepA
    def transit(Hephaestus.Test.V2.StepA, :done, _ctx), do: Hephaestus.Steps.Done
  end

  defmodule Umbrella do
    use Hephaestus.Workflow,
      versions: %{1 => Umbrella.V1, 2 => Umbrella.V2},
      current: 2
  end

  describe "umbrella module" do
    test "generates __versions__/0 with version map" do
      assert Umbrella.__versions__() == %{1 => Umbrella.V1, 2 => Umbrella.V2}
    end

    test "umbrella has __versioned__?/0 = true" do
      assert Umbrella.__versioned__?() == true
    end

    test "umbrella has __version__/0 = nil" do
      assert Umbrella.__version__() == nil
    end

    test "current_version/0 returns compile-time current" do
      assert Umbrella.current_version() == 2
    end

    test "resolve_version(nil) returns current version module" do
      assert Umbrella.resolve_version(nil) == {2, Umbrella.V2}
    end

    test "resolve_version(1) returns V1 module" do
      assert Umbrella.resolve_version(1) == {1, Umbrella.V1}
    end

    test "resolve_version(99) raises ArgumentError" do
      assert_raise ArgumentError, ~r/version 99 not found/, fn ->
        Umbrella.resolve_version(99)
      end
    end

    test "version_for/2 default returns nil" do
      result = Umbrella.version_for(%{1 => Umbrella.V1, 2 => Umbrella.V2}, [])
      assert result == nil
    end

    test "umbrella does not export __graph__/0" do
      refute function_exported?(Umbrella, :__graph__, 0)
    end

    test "umbrella does not export __predecessors__/1" do
      refute function_exported?(Umbrella, :__predecessors__, 1)
    end

    test "umbrella does not export __edges__/0" do
      refute function_exported?(Umbrella, :__edges__, 0)
    end
  end

  describe "umbrella compile-time validations" do
    test "raises when versions key is not a positive integer" do
      assert_raise CompileError, ~r/positive integer/, fn ->
        Code.compile_quoted(
          quote do
            defmodule BadKeysFlow do
              use Hephaestus.Workflow, versions: %{0 => SomeModule}, current: 0
            end
          end
        )
      end
    end

    test "raises when current is not in versions" do
      assert_raise CompileError, ~r/current/, fn ->
        Code.compile_quoted(
          quote do
            defmodule BadCurrentFlow do
              use Hephaestus.Workflow,
                versions: %{
                  1 => Hephaestus.Core.WorkflowVersioningTest.Umbrella.V1
                },
                current: 99
            end
          end
        )
      end
    end

    test "raises when version module __version__/0 doesn't match key" do
      defmodule MismatchV5 do
        use Hephaestus.Workflow, version: 5
        def start, do: Hephaestus.Test.V2.StepA
        def transit(Hephaestus.Test.V2.StepA, :done, _ctx), do: Hephaestus.Steps.Done
      end

      assert_raise CompileError, ~r/mismatch/, fn ->
        Code.compile_quoted(
          quote do
            defmodule MismatchUmbrella do
              use Hephaestus.Workflow,
                versions: %{1 => Hephaestus.Core.WorkflowVersioningTest.MismatchV5},
                current: 1
            end
          end
        )
      end
    end

    test "raises when version module not nested under umbrella namespace" do
      defmodule OutsideNS do
        use Hephaestus.Workflow, version: 1
        def start, do: Hephaestus.Test.V2.StepA
        def transit(Hephaestus.Test.V2.StepA, :done, _ctx), do: Hephaestus.Steps.Done
      end

      assert_raise CompileError, ~r/nested under/, fn ->
        Code.compile_quoted(
          quote do
            defmodule NSUmbrella do
              use Hephaestus.Workflow,
                versions: %{1 => Hephaestus.Core.WorkflowVersioningTest.OutsideNS},
                current: 1
            end
          end
        )
      end
    end
  end

  describe "umbrella with custom version_for/2" do
    test "version_for/2 can be overridden" do
      defmodule CustomResolver.V1 do
        use Hephaestus.Workflow, version: 1
        def start, do: Hephaestus.Test.V2.StepA
        def transit(Hephaestus.Test.V2.StepA, :done, _ctx), do: Hephaestus.Steps.Done
      end

      defmodule CustomResolver.V2 do
        use Hephaestus.Workflow, version: 2
        def start, do: Hephaestus.Test.V2.StepA
        def transit(Hephaestus.Test.V2.StepA, :done, _ctx), do: Hephaestus.Steps.Done
      end

      defmodule CustomResolver do
        use Hephaestus.Workflow,
          versions: %{1 => CustomResolver.V1, 2 => CustomResolver.V2},
          current: 2

        def version_for(%{2 => _}, opts) do
          if opts[:force_v1], do: 1
        end

        def version_for(_, _), do: nil
      end

      # Assert -- callback returns 1 when force_v1 is true
      assert CustomResolver.version_for(CustomResolver.__versions__(), force_v1: true) == 1

      # Assert -- callback returns nil otherwise
      assert CustomResolver.version_for(CustomResolver.__versions__(), []) == nil
    end
  end
end
