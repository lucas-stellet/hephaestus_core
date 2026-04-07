defmodule Hephaestus.Test.TupleConfigHephaestus do
  use Hephaestus,
    storage: {Hephaestus.Runtime.Storage.ETS, [some_opt: :value]},
    runner: Hephaestus.Runtime.Runner.Local
end
