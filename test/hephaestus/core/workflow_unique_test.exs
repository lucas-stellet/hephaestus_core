defmodule Hephaestus.Core.WorkflowUniqueTest do
  use ExUnit.Case, async: true

  alias Hephaestus.Workflow.Unique

  describe "__unique__/0 for standalone workflow" do
    test "returns Unique struct with configured key and default scope" do
      [{module, _}] =
        Code.compile_quoted(
          quote do
            defmodule TestUniqueStandalone do
              use Hephaestus.Workflow, unique: [key: "orderid"]

              @impl true
              def start, do: Hephaestus.Test.V2.StepA

              @impl true
              def transit(Hephaestus.Test.V2.StepA, :done, _ctx), do: Hephaestus.Test.V2.StepB
              def transit(Hephaestus.Test.V2.StepB, :done, _ctx), do: Hephaestus.Steps.Done
            end
          end
        )

      assert %Unique{key: "orderid", scope: :workflow} = module.__unique__()
    end

    test "returns Unique struct with explicit scope" do
      [{module, _}] =
        Code.compile_quoted(
          quote do
            defmodule TestUniqueScopeGlobal do
              use Hephaestus.Workflow, unique: [key: "companyid", scope: :global]

              @impl true
              def start, do: Hephaestus.Test.V2.StepA

              @impl true
              def transit(Hephaestus.Test.V2.StepA, :done, _ctx), do: Hephaestus.Test.V2.StepB
              def transit(Hephaestus.Test.V2.StepB, :done, _ctx), do: Hephaestus.Steps.Done
            end
          end
        )

      assert %Unique{key: "companyid", scope: :global} = module.__unique__()
    end
  end

  describe "__hephaestus__/0" do
    test "returns nil when not configured" do
      [{module, _}] =
        Code.compile_quoted(
          quote do
            defmodule TestUniqueNoHeph do
              use Hephaestus.Workflow, unique: [key: "testid"]

              @impl true
              def start, do: Hephaestus.Test.V2.StepA

              @impl true
              def transit(Hephaestus.Test.V2.StepA, :done, _ctx), do: Hephaestus.Test.V2.StepB
              def transit(Hephaestus.Test.V2.StepB, :done, _ctx), do: Hephaestus.Steps.Done
            end
          end
        )

      assert module.__hephaestus__() == nil
    end

    test "returns configured module when set" do
      [{module, _}] =
        Code.compile_quoted(
          quote do
            defmodule TestUniqueWithHeph do
              use Hephaestus.Workflow,
                unique: [key: "testid"],
                hephaestus: MyApp.CustomHephaestus

              @impl true
              def start, do: Hephaestus.Test.V2.StepA

              @impl true
              def transit(Hephaestus.Test.V2.StepA, :done, _ctx), do: Hephaestus.Test.V2.StepB
              def transit(Hephaestus.Test.V2.StepB, :done, _ctx), do: Hephaestus.Steps.Done
            end
          end
        )

      assert module.__hephaestus__() == MyApp.CustomHephaestus
    end
  end

  describe "compile-time validation" do
    test "raises CompileError when unique is not provided" do
      assert_raise CompileError, ~r/the :unique option is required/, fn ->
        Code.compile_quoted(
          quote do
            defmodule TestNoUnique do
              use Hephaestus.Workflow

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

    test "raises ArgumentError for invalid unique key" do
      assert_raise ArgumentError, ~r/unique key must contain only lowercase/, fn ->
        Code.compile_quoted(
          quote do
            defmodule TestBadKey do
              use Hephaestus.Workflow, unique: [key: "Bad-Key"]

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

    test "raises ArgumentError for invalid scope" do
      assert_raise ArgumentError, ~r/unique scope must be one of/, fn ->
        Code.compile_quoted(
          quote do
            defmodule TestBadScope do
              use Hephaestus.Workflow, unique: [key: "ok", scope: :nope]

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
end
