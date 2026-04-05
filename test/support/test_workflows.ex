defmodule Hephaestus.Test.LinearWorkflow do
  use Hephaestus.Workflow
  alias Hephaestus.Core.Step

  @impl true
  def definition do
    %Hephaestus.Core.Workflow{
      initial_step: :step_a,
      steps: [
        %Step{ref: :step_a, module: Hephaestus.Test.PassStep, transitions: %{"done" => :step_b}},
        %Step{ref: :step_b, module: Hephaestus.Test.PassWithContextStep, transitions: %{"done" => :finish}},
        %Step{ref: :finish, module: Hephaestus.Steps.End}
      ]
    }
  end
end

defmodule Hephaestus.Test.BranchWorkflow do
  use Hephaestus.Workflow
  alias Hephaestus.Core.Step

  @impl true
  def definition do
    %Hephaestus.Core.Workflow{
      initial_step: :check,
      steps: [
        %Step{
          ref: :check,
          module: Hephaestus.Test.BranchStep,
          transitions: %{"approved" => :approve, "rejected" => :reject}
        },
        %Step{ref: :approve, module: Hephaestus.Test.PassStep, transitions: %{"done" => :finish}},
        %Step{ref: :reject, module: Hephaestus.Test.PassStep, transitions: %{"done" => :finish}},
        %Step{ref: :finish, module: Hephaestus.Steps.End}
      ]
    }
  end
end

defmodule Hephaestus.Test.ParallelWorkflow do
  use Hephaestus.Workflow
  alias Hephaestus.Core.Step

  @impl true
  def definition do
    %Hephaestus.Core.Workflow{
      initial_step: :start,
      steps: [
        %Step{
          ref: :start,
          module: Hephaestus.Test.PassStep,
          transitions: %{"done" => [:branch_a, :branch_b, :branch_c]}
        },
        %Step{ref: :branch_a, module: Hephaestus.Test.PassWithContextStep, transitions: %{"done" => :join}},
        %Step{ref: :branch_b, module: Hephaestus.Test.PassWithContextStep, transitions: %{"done" => :join}},
        %Step{ref: :branch_c, module: Hephaestus.Test.PassWithContextStep, transitions: %{"done" => :join}},
        %Step{ref: :join, module: Hephaestus.Test.PassStep, transitions: %{"done" => :finish}},
        %Step{ref: :finish, module: Hephaestus.Steps.End}
      ]
    }
  end
end

defmodule Hephaestus.Test.MixedParallelWorkflow do
  use Hephaestus.Workflow
  alias Hephaestus.Core.Step

  @impl true
  def definition do
    %Hephaestus.Core.Workflow{
      initial_step: :start,
      steps: [
        %Step{
          ref: :start,
          module: Hephaestus.Test.PassStep,
          transitions: %{"done" => [:branch_sync, :branch_async]}
        },
        %Step{
          ref: :branch_sync,
          module: Hephaestus.Test.PassWithContextStep,
          transitions: %{"done" => :join}
        },
        %Step{
          ref: :branch_async,
          module: Hephaestus.Test.AsyncStep,
          transitions: %{"timeout" => :join}
        },
        %Step{ref: :join, module: Hephaestus.Test.PassStep, transitions: %{"done" => :finish}},
        %Step{ref: :finish, module: Hephaestus.Steps.End}
      ]
    }
  end
end

defmodule Hephaestus.Test.AsyncWorkflow do
  use Hephaestus.Workflow
  alias Hephaestus.Core.Step

  @impl true
  def definition do
    %Hephaestus.Core.Workflow{
      initial_step: :step_a,
      steps: [
        %Step{ref: :step_a, module: Hephaestus.Test.PassStep, transitions: %{"done" => :wait}},
        %Step{ref: :wait, module: Hephaestus.Test.AsyncStep, transitions: %{"timeout" => :step_b}},
        %Step{ref: :step_b, module: Hephaestus.Test.PassStep, transitions: %{"done" => :finish}},
        %Step{ref: :finish, module: Hephaestus.Steps.End}
      ]
    }
  end
end

defmodule Hephaestus.Test.EventWorkflow do
  use Hephaestus.Workflow
  alias Hephaestus.Core.Step

  @impl true
  def definition do
    %Hephaestus.Core.Workflow{
      initial_step: :step_a,
      steps: [
        %Step{ref: :step_a, module: Hephaestus.Test.PassStep, transitions: %{"done" => :wait_for_event}},
        %Step{
          ref: :wait_for_event,
          module: Hephaestus.Test.WaitForEventStep,
          transitions: %{"payment_confirmed" => :step_b}
        },
        %Step{
          ref: :step_b,
          module: Hephaestus.Test.PassWithContextStep,
          transitions: %{"done" => :finish}
        },
        %Step{ref: :finish, module: Hephaestus.Steps.End}
      ]
    }
  end
end
