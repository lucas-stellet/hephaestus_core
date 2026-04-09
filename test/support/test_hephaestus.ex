defmodule Hephaestus.Test.Hephaestus do
  use Hephaestus,
    storage: Hephaestus.Runtime.Storage.ETS,
    runner: Hephaestus.Runtime.Runner.Local
end
