defmodule Hephaestus.Core.WorkflowTagsTest do
  use ExUnit.Case, async: true

  describe "runtime accessors" do
    test "tagged workflow returns custom tags" do
      assert Hephaestus.Test.V2.TaggedWorkflow.__tags__() == ["onboarding", "growth"]
    end

    test "tagged workflow returns custom metadata" do
      assert Hephaestus.Test.V2.TaggedWorkflow.__metadata__() == %{
               "team" => "growth",
               "priority" => "high"
             }
    end

    test "untagged workflow returns empty defaults" do
      assert Hephaestus.Test.V2.LinearWorkflow.__tags__() == []
      assert Hephaestus.Test.V2.LinearWorkflow.__metadata__() == %{}
    end

    test "function_exported? returns true for tagged workflow" do
      Code.ensure_loaded!(Hephaestus.Test.V2.TaggedWorkflow)
      assert function_exported?(Hephaestus.Test.V2.TaggedWorkflow, :__tags__, 0)
      assert function_exported?(Hephaestus.Test.V2.TaggedWorkflow, :__metadata__, 0)
    end

    test "function_exported? returns true for untagged workflow (defaults)" do
      Code.ensure_loaded!(Hephaestus.Test.V2.LinearWorkflow)
      assert function_exported?(Hephaestus.Test.V2.LinearWorkflow, :__tags__, 0)
      assert function_exported?(Hephaestus.Test.V2.LinearWorkflow, :__metadata__, 0)
    end
  end

  describe "compile-time validation" do
    test "raises when tags is not a list" do
      assert_raise CompileError, ~r/expected :tags to be a list of strings/, fn ->
        Code.compile_quoted(
          quote do
            defmodule BadTagsNotList do
              use Hephaestus.Workflow, unique: [key: "test"], tags: "not_a_list"
            end
          end
        )
      end
    end

    test "raises when tags contains non-strings" do
      assert_raise CompileError, ~r/expected :tags to be a list of strings/, fn ->
        Code.compile_quoted(
          quote do
            defmodule BadTagsAtoms do
              use Hephaestus.Workflow, unique: [key: "test"], tags: [:atom_tag]
            end
          end
        )
      end
    end

    test "raises when metadata is not a map" do
      assert_raise CompileError, ~r/expected :metadata to be a map/, fn ->
        Code.compile_quoted(
          quote do
            defmodule BadMetaNotMap do
              use Hephaestus.Workflow, unique: [key: "test"], metadata: "not_a_map"
            end
          end
        )
      end
    end

    test "raises when metadata has atom keys" do
      assert_raise CompileError, ~r/expected :metadata keys to be strings/, fn ->
        Code.compile_quoted(
          quote do
            defmodule BadMetaAtomKeys do
              use Hephaestus.Workflow, unique: [key: "test"], metadata: %{atom_key: "value"}
            end
          end
        )
      end
    end

    test "raises when metadata has non-JSON-safe values" do
      assert_raise CompileError, ~r/expected :metadata values to be JSON-safe/, fn ->
        Code.compile_quoted(
          quote do
            defmodule BadMetaValues do
              use Hephaestus.Workflow, unique: [key: "test"], metadata: %{"key" => self()}
            end
          end
        )
      end
    end

    test "accepts nested maps and lists as metadata values" do
      Code.compile_quoted(
        quote do
          defmodule NestedMetaWorkflow do
            use Hephaestus.Workflow,
              unique: [key: "test"],
              metadata: %{
                "nested" => %{"ok" => true, "count" => 42},
                "list" => ["a", "b"],
                "nullable" => nil
              }

            @impl true
            def start, do: Hephaestus.Test.V2.StepA

            @impl true
            def transit(Hephaestus.Test.V2.StepA, :done, _ctx), do: Hephaestus.Test.V2.StepB
            def transit(Hephaestus.Test.V2.StepB, :done, _ctx), do: Hephaestus.Steps.Done
          end
        end
      )
    end
  end
end
