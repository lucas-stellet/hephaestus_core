defmodule Hephaestus.Core.StepDefinitionTest do
  use ExUnit.Case, async: true

  alias Hephaestus.Core.Step
  alias Hephaestus.StepDefinition

  describe "protocol implementation for Core.Step" do
    test "ref/1 returns the step ref" do
      step = %Step{ref: :validate, module: MyApp.Steps.Validate}

      assert StepDefinition.ref(step) == :validate
    end

    test "module/1 returns the step module" do
      step = %Step{ref: :validate, module: MyApp.Steps.Validate}

      assert StepDefinition.module(step) == MyApp.Steps.Validate
    end

    test "config/1 returns nil when no config" do
      step = %Step{ref: :validate, module: MyApp.Steps.Validate}

      assert StepDefinition.config(step) == nil
    end

    test "config/1 returns config map" do
      step = %Step{ref: :notify, module: MyApp.Steps.Notify, config: %{channel: :email}}

      assert StepDefinition.config(step) == %{channel: :email}
    end

    test "transitions/1 returns transitions map" do
      step = %Step{
        ref: :validate,
        module: MyApp.Steps.Validate,
        transitions: %{"valid" => :next, "invalid" => :done}
      }

      assert StepDefinition.transitions(step) == %{"valid" => :next, "invalid" => :done}
    end

    test "raises Protocol.UndefinedError for non-implementing struct" do
      assert_raise Protocol.UndefinedError, fn ->
        StepDefinition.ref(struct(Hephaestus.Core.ExecutionEntry, step_ref: :test, event: "x", timestamp: DateTime.utc_now()))
      end
    end
  end
end
