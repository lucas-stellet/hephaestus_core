defmodule Hephaestus.Uniqueness do
  alias Hephaestus.Workflow.Unique

  def build_id(%Unique{key: key}, value) do
    validate_value!(value)
    "#{key}::#{value}"
  end

  def build_id_with_suffix(%Unique{key: key}, value) do
    validate_value!(value)
    suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{key}::#{value}::#{suffix}"
  end

  def validate_value!(value) when is_binary(value) do
    if simple_value?(value) or uuid_value?(value) do
      :ok
    else
      raise ArgumentError,
            "invalid id value: #{inspect(value)}. Must be [a-z0-9]+ or a valid UUID"
    end
  end

  def extract_value(id) do
    case String.split(id, "::") do
      [_key, value] -> value
      [_key, value, _suffix] -> value
      _ -> raise ArgumentError, "invalid unique id format: #{id}"
    end
  end

  defp simple_value?(value), do: Regex.match?(~r/^[a-z0-9]+$/, value)

  defp uuid_value?(value) do
    Regex.match?(~r/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/, value)
  end
end
