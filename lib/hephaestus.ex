defmodule Hephaestus do
  @moduledoc """
  Entry-point macro for consumer applications.

  Use this module in your application to configure and start the Hephaestus
  workflow engine with your chosen storage and runner adapters.

  ## Usage

      defmodule MyApp.Hephaestus do
        use Hephaestus,
          storage: Hephaestus.Runtime.Storage.ETS,
          runner: Hephaestus.Runtime.Runner.Local
      end

  Then add `MyApp.Hephaestus` to your application's supervision tree:

      children = [
        MyApp.Hephaestus
      ]

  This starts a supervision tree with Registry, DynamicSupervisor,
  TaskSupervisor, and the configured storage adapter.

  ## API

  The generated module exposes:

    * `start_instance/2` - starts a workflow instance
    * `start_instance/3` - starts a workflow instance with options (e.g. telemetry metadata)
    * `resume/2` - resumes a waiting workflow instance

  ## Example

      {:ok, id} = MyApp.Hephaestus.start_instance(MyApp.Workflows.OrderFlow, %{order_id: 123})
      {:ok, id} = MyApp.Hephaestus.start_instance(MyApp.Workflows.OrderFlow, %{order_id: 123}, telemetry_metadata: %{request_id: "req-123"})
      :ok = MyApp.Hephaestus.resume(id, :payment_confirmed)

  ## Options

    * `:storage` - the storage adapter module (default: `Hephaestus.Runtime.Storage.ETS`)
    * `:runner` - the runner adapter module (default: `Hephaestus.Runtime.Runner.Local`)
  """

  @default_storage Hephaestus.Runtime.Storage.ETS
  @default_runner Hephaestus.Runtime.Runner.Local

  defp normalize_adapter({module, opts}) when is_list(opts), do: {module, opts}
  defp normalize_adapter(module), do: {module, []}

  defmacro __using__(opts) do
    {storage_module, storage_opts} =
      opts
      |> Keyword.get(:storage, @default_storage)
      |> normalize_adapter()

    {runner_module, runner_opts} =
      opts
      |> Keyword.get(:runner, @default_runner)
      |> normalize_adapter()

    quote bind_quoted: [
            storage_module: storage_module,
            storage_opts: storage_opts,
            runner_module: runner_module,
            runner_opts: runner_opts
          ] do
      @hephaestus_storage_module storage_module
      @hephaestus_storage_opts storage_opts
      @hephaestus_runner_module runner_module
      @hephaestus_runner_opts runner_opts

      @doc false
      def child_spec(init_arg) do
        registry = Module.concat(__MODULE__, Registry)
        dynamic_supervisor = Module.concat(__MODULE__, DynamicSupervisor)
        task_supervisor = Module.concat(__MODULE__, TaskSupervisor)
        storage_name = Module.concat(__MODULE__, Storage)

        children = [
          {Registry, keys: :unique, name: registry},
          {DynamicSupervisor, name: dynamic_supervisor, strategy: :one_for_one},
          {Task.Supervisor, name: task_supervisor},
          {@hephaestus_storage_module,
           Keyword.merge(@hephaestus_storage_opts, name: storage_name)}
        ]

        hephaestus_name = __MODULE__
        hephaestus_runner = @hephaestus_runner_module
        hephaestus_storage = @hephaestus_storage_module

        %{
          id: __MODULE__,
          start:
            {__MODULE__, :start_link_with_telemetry,
             [
               children,
               [name: __MODULE__, strategy: :one_for_one] ++ List.wrap(init_arg),
               %{name: hephaestus_name, runner: hephaestus_runner, storage: hephaestus_storage}
             ]},
          type: :supervisor
        }
      end

      @doc false
      def start_link_with_telemetry(children, opts, telemetry_info) do
        result = Supervisor.start_link(children, opts)

        case result do
          {:ok, pid} ->
            Hephaestus.Telemetry.runner_init(Map.put(telemetry_info, :pid, pid))
            {:ok, pid}

          other ->
            other
        end
      end

      @doc """
      Starts a workflow instance through the configured runner.

      ## Options

        * `:telemetry_metadata` - a map of custom metadata to attach to all
          telemetry events emitted for this instance (default: `%{}`)

      ## Examples

          {:ok, instance_id} = MyApp.Hephaestus.start_instance(MyApp.Workflows.OrderFlow, %{order_id: 123})
          {:ok, instance_id} = MyApp.Hephaestus.start_instance(MyApp.Workflows.OrderFlow, %{order_id: 123}, telemetry_metadata: %{request_id: "req-456"})
      """
      def start_instance(workflow, context, opts \\ [])
          when is_atom(workflow) and is_map(context) do
        {version, resolved_module} =
          if workflow.__versioned__?() do
            v =
              opts[:version] ||
                workflow.version_for(workflow.__versions__(), opts) ||
                workflow.current_version()

            workflow.resolve_version(v)
          else
            workflow.resolve_version(opts[:version])
          end

        telemetry_metadata = Keyword.get(opts, :telemetry_metadata, %{})

        @hephaestus_runner_module.start_instance(
          resolved_module,
          context,
          Keyword.merge(runner_opts(),
            telemetry_metadata: telemetry_metadata,
            workflow_version: version
          )
        )
      end

      @doc """
      Resumes a waiting workflow instance through the configured runner.

      ## Examples

          :ok = MyApp.Hephaestus.resume(instance_id, :payment_confirmed)
      """
      def resume(instance_id, event) when is_binary(instance_id) and is_atom(event) do
        @hephaestus_runner_module.resume(instance_id, event)
      end

      defp runner_opts do
        [
          storage: {@hephaestus_storage_module, Module.concat(__MODULE__, Storage)},
          registry: Module.concat(__MODULE__, Registry),
          dynamic_supervisor: Module.concat(__MODULE__, DynamicSupervisor),
          task_supervisor: Module.concat(__MODULE__, TaskSupervisor)
        ] ++ @hephaestus_runner_opts
      end
    end
  end
end
