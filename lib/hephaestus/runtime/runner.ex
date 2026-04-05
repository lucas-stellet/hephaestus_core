defmodule Hephaestus.Runtime.Runner do
  @moduledoc """
  Execution adapter contract for workflow instances.
  """

  @callback start_instance(
              workflow :: module(),
              context :: map(),
              opts :: keyword()
            ) :: {:ok, instance_id :: String.t()} | {:error, reason :: term()}

  @callback resume(
              instance_id :: String.t(),
              event :: String.t()
            ) :: :ok | {:error, reason :: term()}

  @callback schedule_resume(
              instance_id :: String.t(),
              step_ref :: atom(),
              delay_ms :: pos_integer()
            ) :: {:ok, reference :: reference()} | {:error, reason :: term()}
end
