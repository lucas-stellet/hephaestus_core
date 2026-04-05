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
    * `resume/2` - resumes a waiting workflow instance

  ## Example

      {:ok, id} = MyApp.Hephaestus.start_instance(MyApp.Workflows.OrderFlow, %{order_id: 123})
      :ok = MyApp.Hephaestus.resume(id, "payment_confirmed")

  ## Options

    * `:storage` - the storage adapter module (default: `Hephaestus.Runtime.Storage.ETS`)
    * `:runner` - the runner adapter module (default: `Hephaestus.Runtime.Runner.Local`)
  """

  @default_storage Hephaestus.Runtime.Storage.ETS
  @default_runner Hephaestus.Runtime.Runner.Local

  defmacro __using__(opts) do
    storage = Keyword.get(opts, :storage, @default_storage)
    runner = Keyword.get(opts, :runner, @default_runner)

    quote bind_quoted: [storage: storage, runner: runner] do
      @hephaestus_storage storage
      @hephaestus_runner runner

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
          {@hephaestus_storage, name: storage_name}
        ]

        %{
          id: __MODULE__,
          start:
            {Supervisor, :start_link,
             [children, [name: __MODULE__, strategy: :one_for_one] ++ List.wrap(init_arg)]},
          type: :supervisor
        }
      end

      @doc """
      Starts a workflow instance through the configured runner.
      """
      def start_instance(workflow, context) when is_atom(workflow) and is_map(context) do
        @hephaestus_runner.start_instance(workflow, context, runner_opts())
      end

      @doc """
      Resumes a waiting workflow instance through the configured runner.
      """
      def resume(instance_id, event) when is_binary(instance_id) and is_binary(event) do
        @hephaestus_runner.resume(instance_id, event)
      end

      defp runner_opts do
        [
          storage: {@hephaestus_storage, Module.concat(__MODULE__, Storage)},
          registry: Module.concat(__MODULE__, Registry),
          dynamic_supervisor: Module.concat(__MODULE__, DynamicSupervisor),
          task_supervisor: Module.concat(__MODULE__, TaskSupervisor)
        ]
      end
    end
  end
end
