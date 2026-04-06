defmodule Hephaestus.Core.WorkflowV2Test do
  use ExUnit.Case, async: true

  describe "valid workflow compilation" do
    test "linear workflow compiles and generates __predecessors__/1" do
      # Arrange & Act
      defmodule LinearFlow do
        use Hephaestus.Workflow

        @impl true
        def start, do: Hephaestus.Test.V2.StepA

        @impl true
        def transit(Hephaestus.Test.V2.StepA, :done, _ctx), do: Hephaestus.Test.V2.StepB
        def transit(Hephaestus.Test.V2.StepB, :done, _ctx), do: Hephaestus.Steps.Done
      end

      # Assert
      preds_b = LinearFlow.__predecessors__(Hephaestus.Test.V2.StepB)
      assert MapSet.member?(preds_b, Hephaestus.Test.V2.StepA)

      preds_end = LinearFlow.__predecessors__(Hephaestus.Steps.Done)
      assert MapSet.member?(preds_end, Hephaestus.Test.V2.StepB)
    end

    test "branch workflow compiles with multiple events from same step" do
      # Arrange & Act
      defmodule BranchFlow do
        use Hephaestus.Workflow

        @impl true
        def start, do: Hephaestus.Test.V2.BranchStep

        @impl true
        def transit(Hephaestus.Test.V2.BranchStep, :approved, _ctx), do: Hephaestus.Test.V2.ApproveStep
        def transit(Hephaestus.Test.V2.BranchStep, :rejected, _ctx), do: Hephaestus.Test.V2.RejectStep
        def transit(Hephaestus.Test.V2.ApproveStep, :done, _ctx), do: Hephaestus.Steps.Done
        def transit(Hephaestus.Test.V2.RejectStep, :done, _ctx), do: Hephaestus.Steps.Done
      end

      # Assert
      preds_approve = BranchFlow.__predecessors__(Hephaestus.Test.V2.ApproveStep)
      assert MapSet.member?(preds_approve, Hephaestus.Test.V2.BranchStep)
    end

    test "fan-out workflow compiles when branches converge" do
      # Arrange & Act
      defmodule FanOutFlow do
        use Hephaestus.Workflow

        @impl true
        def start, do: Hephaestus.Test.V2.StepA

        @impl true
        def transit(Hephaestus.Test.V2.StepA, :done, _ctx), do: [Hephaestus.Test.V2.ParallelA, Hephaestus.Test.V2.ParallelB]
        def transit(Hephaestus.Test.V2.ParallelA, :done, _ctx), do: Hephaestus.Test.V2.JoinStep
        def transit(Hephaestus.Test.V2.ParallelB, :done, _ctx), do: Hephaestus.Test.V2.JoinStep
        def transit(Hephaestus.Test.V2.JoinStep, :done, _ctx), do: Hephaestus.Steps.Done
      end

      # Assert
      preds_join = FanOutFlow.__predecessors__(Hephaestus.Test.V2.JoinStep)
      assert MapSet.member?(preds_join, Hephaestus.Test.V2.ParallelA)
      assert MapSet.member?(preds_join, Hephaestus.Test.V2.ParallelB)
    end

    test "workflow with transit/3 and @targets compiles" do
      # Arrange & Act
      defmodule DynamicFlow do
        use Hephaestus.Workflow

        @impl true
        def start, do: Hephaestus.Test.V2.StepA

        @impl true
        @targets [Hephaestus.Test.V2.StepB, Hephaestus.Test.V2.StepC]
        def transit(Hephaestus.Test.V2.StepA, :done, _ctx), do: Hephaestus.Test.V2.StepB

        def transit(Hephaestus.Test.V2.StepB, :done, _ctx), do: Hephaestus.Steps.Done
        def transit(Hephaestus.Test.V2.StepC, :done, _ctx), do: Hephaestus.Steps.Done
      end

      # Assert
      preds_b = DynamicFlow.__predecessors__(Hephaestus.Test.V2.StepB)
      assert MapSet.member?(preds_b, Hephaestus.Test.V2.StepA)

      preds_c = DynamicFlow.__predecessors__(Hephaestus.Test.V2.StepC)
      assert MapSet.member?(preds_c, Hephaestus.Test.V2.StepA)
    end

    test "__graph__/0 returns a Graph struct" do
      # Arrange
      defmodule GraphFlow do
        use Hephaestus.Workflow

        @impl true
        def start, do: Hephaestus.Test.V2.StepA

        @impl true
        def transit(Hephaestus.Test.V2.StepA, :done, _ctx), do: Hephaestus.Test.V2.StepB
        def transit(Hephaestus.Test.V2.StepB, :done, _ctx), do: Hephaestus.Steps.Done
      end

      # Act
      graph = GraphFlow.__graph__()

      # Assert
      assert %Graph{} = graph
    end
  end

  describe "compile-time validation errors" do
    test "raises on cycle in DAG" do
      # Assert
      assert_raise CompileError, ~r/[Cc]ycle/, fn ->
        Code.compile_quoted(quote do
          defmodule CycleFlow do
            use Hephaestus.Workflow

            @impl true
            def start, do: Hephaestus.Test.V2.StepA

            @impl true
            def transit(Hephaestus.Test.V2.StepA, :done, _ctx), do: Hephaestus.Test.V2.StepB
            def transit(Hephaestus.Test.V2.StepB, :done, _ctx), do: Hephaestus.Test.V2.StepA
          end
        end)
      end
    end

    test "raises on unreachable step" do
      # Assert
      assert_raise CompileError, ~r/[Uu]nreachable/, fn ->
        Code.compile_quoted(quote do
          defmodule OrphanFlow do
            use Hephaestus.Workflow

            @impl true
            def start, do: Hephaestus.Test.V2.StepA

            @impl true
            def transit(Hephaestus.Test.V2.StepA, :done, _ctx), do: Hephaestus.Steps.Done
            def transit(Hephaestus.Test.V2.StepB, :done, _ctx), do: Hephaestus.Steps.Done
          end
        end)
      end
    end

    test "raises on leaf node that is not Hephaestus.Steps.Done" do
      # Assert
      assert_raise CompileError, ~r/Hephaestus\.Steps\.Done/, fn ->
        Code.compile_quoted(quote do
          defmodule NoEndFlow do
            use Hephaestus.Workflow

            @impl true
            def start, do: Hephaestus.Test.V2.StepA

            @impl true
            def transit(Hephaestus.Test.V2.StepA, :done, _ctx), do: Hephaestus.Test.V2.StepB
          end
        end)
      end
    end

    test "raises on fan-out without convergence" do
      # Assert
      assert_raise CompileError, ~r/[Cc]onverg|[Jj]oin/, fn ->
        Code.compile_quoted(quote do
          defmodule NoJoinFlow do
            use Hephaestus.Workflow

            @impl true
            def start, do: Hephaestus.Test.V2.StepA

            @impl true
            def transit(Hephaestus.Test.V2.StepA, :done, _ctx), do: [Hephaestus.Test.V2.ParallelA, Hephaestus.Test.V2.ParallelB]
            def transit(Hephaestus.Test.V2.ParallelA, :done, _ctx), do: Hephaestus.Steps.Done
            def transit(Hephaestus.Test.V2.ParallelB, :done, _ctx), do: Hephaestus.Steps.Done
          end
        end)
      end
    end

    test "raises on event declared in events/0 without transit" do
      # Assert
      assert_raise CompileError, ~r/declares event.*but no transit/, fn ->
        Code.compile_quoted(quote do
          defmodule MissingTransitFlow do
            use Hephaestus.Workflow

            @impl true
            def start, do: Hephaestus.Test.V2.StepWithExtraEvent

            @impl true
            def transit(Hephaestus.Test.V2.StepWithExtraEvent, :done, _ctx), do: Hephaestus.Steps.Done
          end
        end)
      end
    end

    test "raises on transit referencing event not in events/0" do
      # Assert
      assert_raise CompileError, ~r/does not declare.*in events/, fn ->
        Code.compile_quoted(quote do
          defmodule UndeclaredEventFlow do
            use Hephaestus.Workflow

            @impl true
            def start, do: Hephaestus.Test.V2.StepA

            @impl true
            def transit(Hephaestus.Test.V2.StepA, :timeout, _ctx), do: Hephaestus.Steps.Done
          end
        end)
      end
    end

    test "raises on context key collision" do
      # Assert
      assert_raise CompileError, ~r/context key/, fn ->
        Code.compile_quoted(quote do
          defmodule CollisionFlow do
            use Hephaestus.Workflow

            defmodule Foo.Validate do
              @behaviour Hephaestus.Steps.Step

              @impl true
              def events, do: [:done]

              @impl true
              def execute(_instance, _config, _context), do: {:ok, :done}
            end

            defmodule Bar.Validate do
              @behaviour Hephaestus.Steps.Step

              @impl true
              def events, do: [:done]

              @impl true
              def execute(_instance, _config, _context), do: {:ok, :done}
            end

            @impl true
            def start, do: Foo.Validate

            @impl true
            def transit(Foo.Validate, :done, _ctx), do: Bar.Validate
            def transit(Bar.Validate, :done, _ctx), do: Hephaestus.Steps.Done
          end
        end)
      end
    end

    test "raises on non-atom events from events/0" do
      # Assert
      assert_raise CompileError, ~r/events.*atoms/, fn ->
        Code.compile_quoted(quote do
          defmodule NonAtomEventsFlow do
            use Hephaestus.Workflow

            defmodule BadStep do
              @behaviour Hephaestus.Steps.Step

              @impl true
              def events, do: [123]

              @impl true
              def execute(_instance, _config, _context), do: {:ok, :done}
            end

            @impl true
            def start, do: BadStep

            @impl true
            def transit(BadStep, :done, _ctx), do: Hephaestus.Steps.Done
          end
        end)
      end
    end
  end
end
