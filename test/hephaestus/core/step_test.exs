defmodule Hephaestus.Core.StepTest do
  use ExUnit.Case, async: true

  alias Hephaestus.Core.Step

  describe "struct creation" do
    test "creates step with required fields" do
      step = %Step{ref: :validate, module: MyApp.Steps.Validate}

      assert step.ref == :validate
      assert step.module == MyApp.Steps.Validate
      assert step.config == nil
      assert step.transitions == nil
    end

    test "creates step with all fields" do
      step = %Step{
        ref: :notify,
        module: MyApp.Steps.Notify,
        config: %{channel: :email},
        transitions: %{"sent" => :done}
      }

      assert step.config == %{channel: :email}
      assert step.transitions == %{"sent" => :done}
    end

    test "raises when ref is missing" do
      assert_raise ArgumentError, fn ->
        struct!(Step, module: MyApp.Steps.Validate)
      end
    end

    test "raises when module is missing" do
      assert_raise ArgumentError, fn ->
        struct!(Step, ref: :validate)
      end
    end
  end
end
