defmodule Hephaestus.Core.Workflow do
  @moduledoc """
  Workflow definition struct and compile-time validation.

  Workflows are defined as modules using `use Hephaestus.Workflow` with a
  `definition/0` callback that returns a `%Hephaestus.Core.Workflow{}` struct.

  ## Example

      defmodule MyApp.Workflows.OrderFlow do
        use Hephaestus.Workflow
        alias Hephaestus.Core.Step

        @impl true
        def definition do
          %Hephaestus.Core.Workflow{
            initial_step: :validate,
            steps: [
              %Step{ref: :validate, module: MyApp.Steps.Validate, transitions: %{"valid" => :process}},
              %Step{ref: :process, module: MyApp.Steps.Process, transitions: %{"done" => :finish}},
              %Step{ref: :finish, module: Hephaestus.Steps.End}
            ]
          }
        end
      end

  ## Compile-time validation

  The `@before_compile` hook validates the workflow graph at compile time:

    * No duplicate step refs
    * `initial_step` exists in the step list
    * All transition targets reference existing steps
    * No cycles in the graph
    * All steps are reachable from `initial_step`
    * Step configs must be structs (not plain maps)

  ## Generated functions

    * `__step__/1` - returns the step definition for a given ref
    * `__steps_map__/0` - returns all steps as a map keyed by ref
    * `__predecessors__/1` - returns the set of steps that transition into a given step
  """

  @enforce_keys [:initial_step, :steps]
  defstruct [:initial_step, :steps]

  @type t :: %__MODULE__{
          initial_step: atom(),
          steps: list()
        }

  @callback definition() :: t()

  alias Hephaestus.StepDefinition

  @spec validate!(t(), Macro.Env.t() | nil) :: %{
          predecessors: %{optional(atom()) => MapSet.t(atom())},
          steps_map: %{optional(atom()) => term()}
        }
  def validate!(%__MODULE__{} = workflow, env \\ nil) do
    steps = workflow.steps || []
    refs = Enum.map(steps, &StepDefinition.ref/1)

    validate_duplicate_refs!(refs, env)

    steps_map = Map.new(steps, fn step -> {StepDefinition.ref(step), step} end)

    validate_initial_step!(workflow.initial_step, steps_map, env)
    validate_configs!(steps, env)

    adjacency = build_adjacency(steps)

    validate_targets!(adjacency, steps_map, env)
    validate_acyclic!(adjacency, env)
    validate_reachable!(workflow.initial_step, refs, adjacency, env)

    %{
      steps_map: steps_map,
      predecessors: build_predecessors(refs, adjacency)
    }
  end

  defp validate_duplicate_refs!(refs, env) do
    case refs |> Enum.frequencies() |> Enum.find(fn {_ref, count} -> count > 1 end) do
      {ref, _count} -> compile_error!(env, "duplicate step ref #{inspect(ref)} found in steps/0")
      nil -> :ok
    end
  end

  defp validate_initial_step!(initial_step, steps_map, env) do
    if Map.has_key?(steps_map, initial_step) do
      :ok
    else
      compile_error!(env, "initial_step #{inspect(initial_step)} not found in steps/0")
    end
  end

  defp validate_configs!(steps, env) do
    Enum.each(steps, fn step ->
      case StepDefinition.config(step) do
        nil ->
          :ok

        config when is_struct(config) ->
          :ok

        config when is_map(config) ->
          compile_error!(
            env,
            "step #{inspect(StepDefinition.ref(step))} config must be a struct, got: #{inspect(config)}"
          )

        _other ->
          :ok
      end
    end)
  end

  defp validate_targets!(adjacency, steps_map, env) do
    Enum.each(adjacency, fn {source_ref, targets} ->
      Enum.each(targets, fn target_ref ->
        if Map.has_key?(steps_map, target_ref) do
          :ok
        else
          compile_error!(
            env,
            "step #{inspect(target_ref)} referenced in transitions but not defined in steps/0 " <>
              "(from #{inspect(source_ref)})"
          )
        end
      end)
    end)
  end

  defp validate_acyclic!(adjacency, env) do
    {_visited, _stack} =
      Enum.reduce(Map.keys(adjacency), {MapSet.new(), []}, fn ref, {visited, stack} ->
        dfs_cycle!(ref, adjacency, visited, stack, env)
      end)

    :ok
  end

  defp dfs_cycle!(ref, adjacency, visited, stack, env) do
    cond do
      ref in stack ->
        cycle =
          [ref | stack]
          |> Enum.take_while(&(&1 != ref))
          |> Enum.reverse()
          |> Kernel.++([ref])

        compile_error!(env, "cycle detected in workflow graph: #{Enum.map_join(cycle, " -> ", &inspect/1)}")

      MapSet.member?(visited, ref) ->
        {visited, stack}

      true ->
        next_stack = [ref | stack]

        {next_visited, _next_stack} =
          Enum.reduce(Map.get(adjacency, ref, []), {MapSet.put(visited, ref), next_stack}, fn target,
                                                                                               {acc_visited,
                                                                                                acc_stack} ->
            dfs_cycle!(target, adjacency, acc_visited, acc_stack, env)
          end)

        {next_visited, stack}
    end
  end

  defp validate_reachable!(initial_step, refs, adjacency, env) do
    reachable = collect_reachable(MapSet.new([initial_step]), [initial_step], adjacency)

    unreachable_refs =
      refs
      |> Enum.reject(&MapSet.member?(reachable, &1))
      |> Enum.sort()

    case unreachable_refs do
      [] ->
        :ok

      refs ->
        compile_error!(
          env,
          "unreachable steps from initial_step #{inspect(initial_step)}: #{Enum.map_join(refs, ", ", &inspect/1)}"
        )
    end
  end

  defp collect_reachable(visited, [], _adjacency), do: visited

  defp collect_reachable(visited, [ref | rest], adjacency) do
    {next_visited, next_queue} =
      Enum.reduce(Map.get(adjacency, ref, []), {visited, rest}, fn target, {acc_visited, acc_queue} ->
        if MapSet.member?(acc_visited, target) do
          {acc_visited, acc_queue}
        else
          {MapSet.put(acc_visited, target), acc_queue ++ [target]}
        end
      end)

    collect_reachable(next_visited, next_queue, adjacency)
  end

  defp build_predecessors(refs, adjacency) do
    initial = Map.new(refs, fn ref -> {ref, MapSet.new()} end)

    Enum.reduce(adjacency, initial, fn {source_ref, targets}, predecessors ->
      Enum.reduce(targets, predecessors, fn target_ref, acc ->
        Map.update(acc, target_ref, MapSet.new([source_ref]), &MapSet.put(&1, source_ref))
      end)
    end)
  end

  defp build_adjacency(steps) do
    Map.new(steps, fn step ->
      {StepDefinition.ref(step), normalize_targets(StepDefinition.transitions(step))}
    end)
  end

  defp normalize_targets(nil), do: []

  defp normalize_targets(transitions) when is_map(transitions) do
    Enum.flat_map(transitions, fn {_event, target} ->
      case target do
        target_ref when is_atom(target_ref) -> [target_ref]
        target_refs when is_list(target_refs) -> target_refs
        _other -> []
      end
    end)
  end

  defp normalize_targets(_other), do: []

  defp compile_error!(nil, message), do: raise(CompileError, description: message)

  defp compile_error!(env, message) do
    raise CompileError,
      file: env.file,
      line: env.line,
      description: message
  end
end

defmodule Hephaestus.Workflow do
  defmacro __using__(_opts) do
    quote do
      @behaviour Hephaestus.Core.Workflow
      @before_compile Hephaestus.Workflow
    end
  end

  defmacro __before_compile__(env) do
    {:v1, :def, _meta, [{_clause_meta, _args, _guards, definition_body}]} =
      Module.get_definition(env.module, {:definition, 0})

    %{steps_map: steps_map, predecessors: predecessors} =
      definition_body
      |> Code.eval_quoted([], env)
      |> elem(0)
      |> Hephaestus.Core.Workflow.validate!(env)

    steps_map_ast = Macro.escape(steps_map)
    predecessors_ast = Macro.escape(predecessors)

    quote do
      def __steps_map__, do: unquote(steps_map_ast)
      def __step__(ref), do: Map.get(__steps_map__(), ref)
      def __predecessors__(ref), do: Map.get(unquote(predecessors_ast), ref, MapSet.new())
    end
  end
end
