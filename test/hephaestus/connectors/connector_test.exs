defmodule Hephaestus.Connectors.ConnectorTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  # Mock connector implementing the behaviour
  defmodule TestConnector do
    @behaviour Hephaestus.Connectors.Connector

    @impl true
    def execute(:get_task, params, _config) do
      {:ok, %{id: params[:task_id], title: "Test Task"}}
    end

    def execute(:create_task, params, _config) do
      {:ok, %{id: "new_123", title: params[:title]}}
    end

    def execute(_action, _params, _config) do
      {:error, :unsupported_action}
    end

    @impl true
    def supported_actions, do: [:get_task, :create_task]
  end

  describe "behaviour contract" do
    test "defines execute/3 and supported_actions/0 callbacks" do
      callbacks = Hephaestus.Connectors.Connector.behaviour_info(:callbacks)

      assert {:execute, 3} in callbacks
      assert {:supported_actions, 0} in callbacks
    end

    test "exports the connector types" do
      {:ok, types} = Code.Typespec.fetch_types(Hephaestus.Connectors.Connector)
      exported_types = Enum.map(types, fn {kind, {name, _, _}} -> {kind, name} end)

      assert {:type, :action} in exported_types
      assert {:type, :params} in exported_types
      assert {:type, :config} in exported_types
      assert {:type, :result} in exported_types
      assert {:type, :error_reason} in exported_types
    end

    test "execute/3 returns ok with result map" do
      params = %{task_id: "123"}
      config = %{api_key: "secret"}

      result = TestConnector.execute(:get_task, params, config)

      assert {:ok, %{id: "123", title: "Test Task"}} = result
    end

    test "execute/3 returns error for unsupported action" do
      result = TestConnector.execute(:unknown, %{}, %{})

      assert {:error, :unsupported_action} = result
    end

    test "supported_actions/0 returns list of atoms" do
      actions = TestConnector.supported_actions()

      assert :get_task in actions
      assert :create_task in actions
      assert length(actions) == 2
    end

    test "compiler warns when an implementation omits a required callback" do
      warning =
        capture_io(:stderr, fn ->
          Code.compile_string("""
          defmodule MissingCallbackConnector do
            @behaviour Hephaestus.Connectors.Connector

            def execute(_action, _params, _config) do
              {:ok, %{}}
            end
          end
          """)
        end)

      assert warning =~ "MissingCallbackConnector"
      assert warning =~ "supported_actions/0"
    end
  end
end
