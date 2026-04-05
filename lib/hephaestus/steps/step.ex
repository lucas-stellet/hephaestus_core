defmodule Hephaestus.Steps.Step do
  alias Hephaestus.Core.{Context, Instance}

  @type config :: map() | nil
  @type event :: String.t()
  @type context_updates :: map()
  @type result ::
          {:ok, event()}
          | {:ok, event(), context_updates()}
          | {:async}
          | {:error, term()}

  @callback execute(instance :: Instance.t(), config :: config(), context :: Context.t()) :: result()
end
