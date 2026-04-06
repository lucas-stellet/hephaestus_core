defmodule Hephaestus.Steps.StepBehaviourTest do
  use ExUnit.Case, async: true

  describe "behaviour callbacks" do
    test "module implementing events/0 and execute/3 satisfies behaviour" do
      defmodule FullStep do
        @behaviour Hephaestus.Steps.Step

        @impl true
        def events, do: [:done, :failed]

        @impl true
        def execute(_instance, _config, _context), do: {:ok, :done}
      end

      events = FullStep.events()
      result = FullStep.execute(nil, nil, nil)

      assert events == [:done, :failed]
      assert {:ok, :done} = result
    end

    test "module implementing optional step_key/0 returns custom key" do
      defmodule StepWithKey do
        @behaviour Hephaestus.Steps.Step

        @impl true
        def events, do: [:done]

        @impl true
        def step_key, do: :custom_key

        @impl true
        def execute(_instance, _config, _context), do: {:ok, :done}
      end

      key = StepWithKey.step_key()

      assert key == :custom_key
    end

    test "module without step_key/0 does not export it" do
      defmodule StepWithoutKey do
        @behaviour Hephaestus.Steps.Step

        @impl true
        def events, do: [:done]

        @impl true
        def execute(_instance, _config, _context), do: {:ok, :done}
      end

      refute function_exported?(StepWithoutKey, :step_key, 0)
    end
  end
end
