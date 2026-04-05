defmodule Hephaestus.Core.WorkflowValidationTest do
  use ExUnit.Case, async: true

  defmodule FakeStep do
  end

  defmodule FakeEnd do
  end

  defmodule ValidConfig do
    defstruct [:value]
  end

  describe "valid workflow compilation" do
    test "linear workflow compiles successfully" do
      defmodule ValidLinear do
        use Hephaestus.Workflow

        @impl true
        def definition do
              %Hephaestus.Core.Workflow{
            initial_step: :start,
            steps: [
              %Hephaestus.Core.Step{ref: :start, module: FakeStep, transitions: %{"done" => :finish}},
              %Hephaestus.Core.Step{ref: :finish, module: FakeEnd}
            ]
          }
        end
      end

      assert ValidLinear.definition().initial_step == :start
    end

    test "branching workflow compiles successfully" do
      defmodule ValidBranch do
        use Hephaestus.Workflow

        @impl true
        def definition do
          %Hephaestus.Core.Workflow{
            initial_step: :check,
            steps: [
              %Hephaestus.Core.Step{
                ref: :check,
                module: FakeStep,
                transitions: %{"yes" => :approve, "no" => :reject}
              },
              %Hephaestus.Core.Step{ref: :approve, module: FakeStep, transitions: %{"done" => :finish}},
              %Hephaestus.Core.Step{ref: :reject, module: FakeStep, transitions: %{"done" => :finish}},
              %Hephaestus.Core.Step{ref: :finish, module: FakeEnd}
            ]
          }
        end
      end

      assert ValidBranch.definition().initial_step == :check
    end

    test "fan-out workflow compiles successfully" do
      defmodule ValidFanOut do
        use Hephaestus.Workflow

        @impl true
        def definition do
          %Hephaestus.Core.Workflow{
            initial_step: :start,
            steps: [
              %Hephaestus.Core.Step{ref: :start, module: FakeStep, transitions: %{"go" => [:step_a, :step_b]}},
              %Hephaestus.Core.Step{ref: :step_a, module: FakeStep, transitions: %{"done" => :join}},
              %Hephaestus.Core.Step{ref: :step_b, module: FakeStep, transitions: %{"done" => :join}},
              %Hephaestus.Core.Step{ref: :join, module: FakeStep, transitions: %{"done" => :finish}},
              %Hephaestus.Core.Step{ref: :finish, module: FakeEnd}
            ]
          }
        end
      end

      assert MapSet.member?(ValidFanOut.__predecessors__(:join), :step_a)
      assert MapSet.member?(ValidFanOut.__predecessors__(:join), :step_b)
    end
  end

  describe "invalid workflow detection" do
    test "raises on duplicate step refs" do
      assert_raise CompileError, ~r/duplicate.*ref/i, fn ->
        defmodule DuplicateRefs do
          use Hephaestus.Workflow

          @impl true
          def definition do
            %Hephaestus.Core.Workflow{
              initial_step: :start,
              steps: [
                %Hephaestus.Core.Step{ref: :start, module: FakeStep, transitions: %{"done" => :finish}},
                %Hephaestus.Core.Step{ref: :start, module: FakeEnd}
              ]
            }
          end
        end
      end
    end

    test "raises when initial_step does not exist in steps" do
      assert_raise CompileError, ~r/initial_step.*not found/i, fn ->
        defmodule MissingInitial do
          use Hephaestus.Workflow

          @impl true
          def definition do
            %Hephaestus.Core.Workflow{
              initial_step: :nonexistent,
              steps: [
                %Hephaestus.Core.Step{ref: :start, module: FakeStep}
              ]
            }
          end
        end
      end
    end

    test "raises when transition targets nonexistent step" do
      assert_raise CompileError, ~r/target.*not found|referenced.*not defined/i, fn ->
        defmodule MissingTarget do
          use Hephaestus.Workflow

          @impl true
          def definition do
            %Hephaestus.Core.Workflow{
              initial_step: :start,
              steps: [
                %Hephaestus.Core.Step{ref: :start, module: FakeStep, transitions: %{"done" => :nonexistent}},
                %Hephaestus.Core.Step{ref: :finish, module: FakeEnd}
              ]
            }
          end
        end
      end
    end

    test "raises when graph contains a cycle" do
      assert_raise CompileError, ~r/cycle/i, fn ->
        defmodule CyclicWorkflow do
          use Hephaestus.Workflow

          @impl true
          def definition do
            %Hephaestus.Core.Workflow{
              initial_step: :a,
              steps: [
                %Hephaestus.Core.Step{ref: :a, module: FakeStep, transitions: %{"done" => :b}},
                %Hephaestus.Core.Step{ref: :b, module: FakeStep, transitions: %{"done" => :a}}
              ]
            }
          end
        end
      end
    end

    test "raises when step is not reachable from initial_step" do
      assert_raise CompileError, ~r/orphan|unreachable/i, fn ->
        defmodule OrphanStep do
          use Hephaestus.Workflow

          @impl true
          def definition do
            %Hephaestus.Core.Workflow{
              initial_step: :start,
              steps: [
                %Hephaestus.Core.Step{ref: :start, module: FakeStep, transitions: %{"done" => :finish}},
                %Hephaestus.Core.Step{ref: :orphan, module: FakeStep, transitions: %{"done" => :finish}},
                %Hephaestus.Core.Step{ref: :finish, module: FakeEnd}
              ]
            }
          end
        end
      end
    end

    test "raises when config is a plain map instead of struct" do
      assert_raise CompileError, ~r/config.*struct/i, fn ->
        defmodule PlainMapConfig do
          use Hephaestus.Workflow

          @impl true
          def definition do
            %Hephaestus.Core.Workflow{
              initial_step: :start,
              steps: [
                %Hephaestus.Core.Step{
                  ref: :start,
                  module: FakeStep,
                  config: %{bad: "config"},
                  transitions: %{"done" => :finish}
                },
                %Hephaestus.Core.Step{ref: :finish, module: FakeEnd}
              ]
            }
          end
        end
      end
    end
  end

  describe "generated functions" do
    test "__step__/1 returns step definition by ref" do
      defmodule StepLookup do
        use Hephaestus.Workflow

        @impl true
        def definition do
          %Hephaestus.Core.Workflow{
            initial_step: :start,
            steps: [
              %Hephaestus.Core.Step{
                ref: :start,
                module: FakeStep,
                config: %ValidConfig{value: "ok"},
                transitions: %{"done" => :finish}
              },
              %Hephaestus.Core.Step{ref: :finish, module: FakeEnd}
            ]
          }
        end
      end

      step = StepLookup.__step__(:start)

      assert Hephaestus.StepDefinition.ref(step) == :start
      assert Hephaestus.StepDefinition.module(step) == FakeStep
    end

    test "__steps_map__/0 returns all steps indexed by ref" do
      defmodule StepsMapWorkflow do
        use Hephaestus.Workflow

        @impl true
        def definition do
          %Hephaestus.Core.Workflow{
            initial_step: :start,
            steps: [
              %Hephaestus.Core.Step{ref: :start, module: FakeStep, transitions: %{"done" => :finish}},
              %Hephaestus.Core.Step{ref: :finish, module: FakeEnd}
            ]
          }
        end
      end

      steps_map = StepsMapWorkflow.__steps_map__()

      assert Map.has_key?(steps_map, :start)
      assert Map.has_key?(steps_map, :finish)
      assert map_size(steps_map) == 2
    end

    test "__predecessors__/1 returns empty set for initial step" do
      defmodule InitialPredsWorkflow do
        use Hephaestus.Workflow

        @impl true
        def definition do
          %Hephaestus.Core.Workflow{
            initial_step: :start,
            steps: [
              %Hephaestus.Core.Step{ref: :start, module: FakeStep, transitions: %{"done" => :finish}},
              %Hephaestus.Core.Step{ref: :finish, module: FakeEnd}
            ]
          }
        end
      end

      preds = InitialPredsWorkflow.__predecessors__(:start)

      assert MapSet.size(preds) == 0
    end

    test "__predecessors__/1 returns predecessors for fan-in step" do
      defmodule FanInPreds do
        use Hephaestus.Workflow

        @impl true
        def definition do
          %Hephaestus.Core.Workflow{
            initial_step: :start,
            steps: [
              %Hephaestus.Core.Step{ref: :start, module: FakeStep, transitions: %{"go" => [:a, :b]}},
              %Hephaestus.Core.Step{ref: :a, module: FakeStep, transitions: %{"done" => :join}},
              %Hephaestus.Core.Step{ref: :b, module: FakeStep, transitions: %{"done" => :join}},
              %Hephaestus.Core.Step{ref: :join, module: FakeStep, transitions: %{"done" => :finish}},
              %Hephaestus.Core.Step{ref: :finish, module: FakeEnd}
            ]
          }
        end
      end

      preds = FanInPreds.__predecessors__(:join)

      assert MapSet.equal?(preds, MapSet.new([:a, :b]))
    end
  end
end
