defmodule Hephaestus.Runtime.Storage do
  @moduledoc """
  Persistence adapter contract for workflow instances.
  """

  alias Hephaestus.Core.Instance

  @doc """
  Retrieves a workflow instance by its unique identifier.

  Returns `{:ok, instance}` if found, or `{:error, :not_found}` if no instance
  matches the given `instance_id`.
  """
  @callback get(instance_id :: String.t()) :: {:ok, Instance.t()} | {:error, :not_found}

  @doc """
  Persists a workflow instance.

  Inserts the instance if it does not exist, or overwrites it if an instance with
  the same ID is already stored.
  """
  @callback put(instance :: Instance.t()) :: :ok

  @doc """
  Deletes a workflow instance by its unique identifier.

  The operation is idempotent — deleting a non-existent instance is not an error.
  """
  @callback delete(instance_id :: String.t()) :: :ok

  @doc """
  Returns all workflow instances that match the given filters.

  `filters` is a keyword list where each key corresponds to an instance field
  (e.g., `:status`, `:workflow`). Only instances matching **all** provided filters
  are returned. An empty filter list returns all stored instances.
  """
  @callback query(filters :: keyword()) :: [Instance.t()]
end
