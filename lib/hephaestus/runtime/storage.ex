defmodule Hephaestus.Runtime.Storage do
  @moduledoc """
  Persistence adapter contract for workflow instances.
  """

  alias Hephaestus.Core.Instance

  @callback get(instance_id :: String.t()) :: {:ok, Instance.t()} | {:error, :not_found}
  @callback put(instance :: Instance.t()) :: :ok
  @callback delete(instance_id :: String.t()) :: :ok
  @callback query(filters :: keyword()) :: [Instance.t()]
end
