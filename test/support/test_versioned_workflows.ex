defmodule Hephaestus.Test.Versioned.V1 do
  use Hephaestus.Workflow, version: 1

  @impl true
  def start, do: Hephaestus.Test.V2.StepA

  @impl true
  def transit(Hephaestus.Test.V2.StepA, :done, _ctx), do: Hephaestus.Steps.Done
end

defmodule Hephaestus.Test.Versioned.V2 do
  use Hephaestus.Workflow, version: 2

  @impl true
  def start, do: Hephaestus.Test.V2.StepA

  @impl true
  def transit(Hephaestus.Test.V2.StepA, :done, _ctx), do: Hephaestus.Steps.Done
end

defmodule Hephaestus.Test.Versioned do
  use Hephaestus.Workflow,
    versions: %{1 => __MODULE__.V1, 2 => __MODULE__.V2},
    current: 2
end

defmodule Hephaestus.Test.VersionedWithCallback.V1 do
  use Hephaestus.Workflow, version: 1

  @impl true
  def start, do: Hephaestus.Test.V2.StepA

  @impl true
  def transit(Hephaestus.Test.V2.StepA, :done, _ctx), do: Hephaestus.Steps.Done
end

defmodule Hephaestus.Test.VersionedWithCallback.V2 do
  use Hephaestus.Workflow, version: 2

  @impl true
  def start, do: Hephaestus.Test.V2.StepA

  @impl true
  def transit(Hephaestus.Test.V2.StepA, :done, _ctx), do: Hephaestus.Steps.Done
end

defmodule Hephaestus.Test.VersionedWithCallback do
  use Hephaestus.Workflow,
    versions: %{
      1 => __MODULE__.V1,
      2 => __MODULE__.V2
    },
    current: 2

  def version_for(_versions, opts) do
    if opts[:force_v1], do: 1
  end
end
