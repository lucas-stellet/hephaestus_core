defmodule Hephaestus.Runtime.Storage.ETS do
  @moduledoc """
  ETS-backed storage adapter for workflow instances.
  """

  use GenServer

  alias Hephaestus.Core.Instance
  alias Hephaestus.Runtime.Storage

  @behaviour Storage

  @type server :: GenServer.server()
  @type filters :: keyword()
  @type state :: %{table: atom()}

  @doc """
  Starts the ETS storage process and links it to the caller.

  ## Options

    * `:name` - the registered process name (defaults to `#{inspect(__MODULE__)}`).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{name: name}, name: name)
  end

  @doc """
  Retrieves a workflow instance by ID from the default ETS server.

  Looks up the instance in the named ETS table via a `GenServer.call/2`.
  Returns `{:ok, instance}` if found, or `{:error, :not_found}` otherwise.
  """
  @impl Storage
  @spec get(String.t()) :: {:ok, Instance.t()} | {:error, :not_found}
  def get(instance_id), do: get(__MODULE__, instance_id)

  @doc """
  Retrieves a workflow instance by ID from the given `server`.
  """
  @spec get(server(), String.t()) :: {:ok, Instance.t()} | {:error, :not_found}
  def get(server, instance_id) when is_binary(instance_id) do
    GenServer.call(server, {:get, instance_id})
  end

  @doc """
  Persists a workflow instance in the default ETS server.

  Inserts or overwrites the instance keyed by its ID using `:ets.insert/2`.
  """
  @impl Storage
  @spec put(Instance.t()) :: :ok
  def put(instance), do: put(__MODULE__, instance)

  @doc """
  Persists a workflow instance in the given `server`.
  """
  @spec put(server(), Instance.t()) :: :ok
  def put(server, %Instance{} = instance) do
    GenServer.call(server, {:put, instance})
  end

  @doc """
  Deletes a workflow instance by ID from the default ETS server.

  Removes the entry from the ETS table via `:ets.delete/2`. The operation is
  idempotent — deleting a non-existent instance is not an error.
  """
  @impl Storage
  @spec delete(String.t()) :: :ok
  def delete(instance_id), do: delete(__MODULE__, instance_id)

  @doc """
  Deletes a workflow instance by ID from the given `server`.
  """
  @spec delete(server(), String.t()) :: :ok
  def delete(server, instance_id) when is_binary(instance_id) do
    GenServer.call(server, {:delete, instance_id})
  end

  @doc """
  Returns all workflow instances matching the given filters from the default ETS server.

  Performs a full table scan with `:ets.tab2list/1` and filters in-memory by
  `:status` and `:workflow` fields. An empty filter list returns all stored instances.
  """
  @impl Storage
  @spec query(filters()) :: [Instance.t()]
  def query(filters), do: query(__MODULE__, filters)

  @doc """
  Returns all workflow instances matching the given filters from the given `server`.
  """
  @spec query(server(), filters()) :: [Instance.t()]
  def query(server, filters) when is_list(filters) do
    GenServer.call(server, {:query, filters})
  end

  @impl GenServer
  @spec init(%{name: atom()}) :: {:ok, state()}
  def init(%{name: name}) when is_atom(name) do
    table = :ets.new(name, [:set, :named_table, :protected])
    {:ok, %{table: table}}
  end

  @impl GenServer
  def handle_call({:get, instance_id}, _from, %{table: table} = state) do
    result =
      case :ets.lookup(table, instance_id) do
        [{^instance_id, %Instance{} = instance}] -> {:ok, instance}
        [] -> {:error, :not_found}
      end

    {:reply, result, state}
  end

  def handle_call({:put, %Instance{id: id} = instance}, _from, %{table: table} = state) do
    true = :ets.insert(table, {id, instance})
    {:reply, :ok, state}
  end

  def handle_call({:delete, instance_id}, _from, %{table: table} = state) do
    true = :ets.delete(table, instance_id)
    {:reply, :ok, state}
  end

  def handle_call({:query, filters}, _from, %{table: table} = state) do
    instances =
      table
      |> :ets.tab2list()
      |> Enum.map(fn {_id, instance} -> instance end)
      |> Enum.filter(&matches_filters?(&1, filters))

    {:reply, instances, state}
  end

  defp matches_filters?(%Instance{} = instance, filters) do
    Enum.all?(filters, fn
      {:status, status} -> instance.status == status
      {:workflow, workflow} -> instance.workflow == workflow
      {_key, _value} -> true
    end)
  end
end
