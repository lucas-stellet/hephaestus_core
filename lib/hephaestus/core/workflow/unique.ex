defmodule Hephaestus.Workflow.Unique do
  @enforce_keys [:key]
  defstruct [:key, scope: :workflow]

  @key_format ~r/^[a-z0-9]+$/
  @valid_scopes [:workflow, :version, :global, :none]

  @type scope :: :workflow | :version | :global | :none
  @type t :: %__MODULE__{key: String.t(), scope: scope()}

  def new!(opts) do
    unique = struct!(__MODULE__, opts)
    validate_key!(unique.key)
    validate_scope!(unique.scope)
    unique
  end

  defp validate_key!(key) when is_binary(key) do
    unless Regex.match?(@key_format, key) do
      raise ArgumentError,
            "unique key must contain only lowercase letters and numbers [a-z0-9], got: #{inspect(key)}"
    end
  end

  defp validate_key!(key) do
    raise ArgumentError, "unique key must be a string, got: #{inspect(key)}"
  end

  defp validate_scope!(scope) when scope in @valid_scopes, do: :ok

  defp validate_scope!(scope) do
    raise ArgumentError,
          "unique scope must be one of #{inspect(@valid_scopes)}, got: #{inspect(scope)}"
  end
end
