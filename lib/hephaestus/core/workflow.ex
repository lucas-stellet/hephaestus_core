defmodule Hephaestus.Core.Workflow do
  @moduledoc """
  Behaviour and compile-time validation helpers for workflow modules.

  Workflows are declared with `use Hephaestus.Workflow` and must expose:

    * `start/0`
    * `transit/3` — static clauses ignore context with `_ctx`, dynamic clauses use `@targets`

  The `Hephaestus.Workflow` macro extracts the workflow DAG at compile time,
  validates it, and generates helper functions for runtime coordination.
  """

  @typedoc "Static or configured step target."
  @type target :: module() | {module(), map() | struct()}

  @callback start() :: target()

  @callback transit(from :: module(), event :: atom(), context :: Hephaestus.Core.Context.t()) ::
              target() | [target()] | nil

  @end_step Hephaestus.Steps.Done

  @type edge :: %{
          from: module(),
          event: atom(),
          targets: [module()],
          dynamic?: boolean
        }

  @spec validate!(module(), module() | {module(), map() | struct()}, [edge()], Macro.Env.t()) ::
          %{graph: Graph.t(), predecessors: %{optional(module()) => MapSet.t(module())}}
  def validate!(workflow_module, start, edges, env) do
    start_module = normalize_start_module!(start, env)
    graph = build_graph(start_module, edges)

    validate_acyclic!(graph, env)
    validate_reachable!(graph, start_module, env)
    validate_leaf_nodes!(graph, env)
    validate_fan_out_convergence!(edges, graph, env)
    validate_context_key_collisions!(graph, env)
    validate_events!(workflow_module, graph, edges, env)

    %{
      graph: graph,
      predecessors: build_predecessors(graph)
    }
  end

  defp normalize_start_module!(module, _env) when is_atom(module), do: module
  defp normalize_start_module!({module, _config}, _env) when is_atom(module), do: module

  defp normalize_start_module!(other, env) do
    compile_error!(env, "start/0 must return a step module or {step_module, config}, got: #{inspect(other)}")
  end

  defp build_graph(start_module, edges) do
    vertices =
      edges
      |> Enum.flat_map(fn %{from: from, targets: targets} -> [from | targets] end)
      |> Kernel.++([start_module])
      |> Enum.uniq()

    graph =
      Graph.new(type: :directed)
      |> Graph.add_vertices(vertices)

    Enum.reduce(edges, graph, fn %{from: from, targets: targets}, acc ->
      Enum.reduce(targets, acc, fn target, graph_acc ->
        Graph.add_edge(graph_acc, from, target)
      end)
    end)
  end

  defp validate_acyclic!(graph, env) do
    unless Graph.is_acyclic?(graph) do
      compile_error!(env, "cycle detected in workflow graph")
    end
  end

  defp validate_reachable!(graph, start_module, env) do
    reachable = MapSet.new([start_module | Graph.reachable_neighbors(graph, [start_module])])

    unreachable =
      graph
      |> Graph.vertices()
      |> Enum.reject(&MapSet.member?(reachable, &1))
      |> Enum.sort()

    if unreachable != [] do
      compile_error!(
        env,
        "unreachable steps from start/0 #{inspect(start_module)}: #{Enum.map_join(unreachable, ", ", &inspect/1)}"
      )
    end
  end

  defp validate_leaf_nodes!(graph, env) do
    invalid_leaves =
      graph
      |> Graph.vertices()
      |> Enum.filter(&(Graph.out_neighbors(graph, &1) == []))
      |> Enum.reject(&(&1 == @end_step))

    case invalid_leaves do
      [] ->
        :ok

      leaves ->
        compile_error!(
          env,
          "path terminates at #{Enum.map_join(leaves, ", ", &inspect/1)}, which is not #{inspect(@end_step)}"
        )
    end
  end

  defp validate_fan_out_convergence!(edges, graph, env) do
    Enum.each(edges, fn
      %{from: from, targets: targets, dynamic?: false} when length(targets) > 1 ->
        reachable_sets = Enum.map(targets, &reachable_with_self(graph, &1))
        common = Enum.reduce(reachable_sets, &MapSet.intersection/2) |> MapSet.delete(@end_step)

        if MapSet.size(common) == 0 do
          compile_error!(
            env,
            "fan-out branches from #{inspect(from)} must converge before #{inspect(@end_step)}"
          )
        end

      _edge ->
        :ok
    end)
  end

  defp reachable_with_self(graph, vertex) do
    MapSet.new([vertex | Graph.reachable_neighbors(graph, [vertex])])
  end

  defp validate_context_key_collisions!(graph, env) do
    graph
    |> Graph.vertices()
    |> Enum.reject(&(&1 == @end_step))
    |> Enum.group_by(&context_key_for/1)
    |> Enum.each(fn
      {_key, [_single]} ->
        :ok

      {key, modules} ->
        compile_error!(
          env,
          "context key collision for #{inspect(key)}: #{Enum.map_join(modules, ", ", &inspect/1)}"
        )
    end)
  end

  defp validate_events!(workflow_module, graph, edges, env) do
    transit_events =
      Enum.reduce(edges, %{}, fn %{from: from, event: event}, acc ->
        Map.update(acc, from, MapSet.new([event]), &MapSet.put(&1, event))
      end)

    graph
    |> Graph.vertices()
    |> Enum.each(fn
      @end_step ->
        :ok

      step_module ->
        validate_step_events!(workflow_module, step_module, Map.get(transit_events, step_module, MapSet.new()), env)
    end)
  end

  defp validate_step_events!(workflow_module, step_module, transit_events, env) do
    ensure_events_callback!(step_module, env)
    declared_events = step_module.events()

    unless is_list(declared_events) and Enum.all?(declared_events, &is_atom/1) do
      compile_error!(env, "#{inspect(step_module)} events/0 must return a list of atoms")
    end

    declared_set = MapSet.new(declared_events)

    Enum.each(transit_events, fn event ->
      unless MapSet.member?(declared_set, event) do
        compile_error!(
          env,
          "#{inspect(step_module)} does not declare #{inspect(event)} in events/0"
        )
      end
    end)

    Enum.each(declared_events, fn event ->
      unless MapSet.member?(transit_events, event) do
        compile_error!(
          env,
          "#{inspect(step_module)} declares event #{inspect(event)} but no transit is defined in #{inspect(workflow_module)}"
        )
      end
    end)
  end

  defp ensure_events_callback!(step_module, env) do
    ensure_step_module_loaded!(step_module, env)

    unless function_exported?(step_module, :events, 0) do
      compile_error!(env, "#{inspect(step_module)} must implement events/0")
    end
  end

  defp build_predecessors(graph) do
    Map.new(Graph.vertices(graph), fn vertex ->
      {vertex, MapSet.new(Graph.in_neighbors(graph, vertex))}
    end)
  end

  defp context_key_for(module) do
    ensure_step_module_loaded!(module, nil)

    if function_exported?(module, :step_key, 0) do
      module.step_key()
    else
      module
      |> Module.split()
      |> List.last()
      |> Macro.underscore()
      |> String.to_atom()
    end
  end

  defp ensure_step_module_loaded!(step_module, nil) do
    case Code.ensure_compiled(step_module) do
      {:module, _module} -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp ensure_step_module_loaded!(step_module, env) do
    case Code.ensure_compiled(step_module) do
      {:module, _module} ->
        :ok

      {:error, reason} ->
        compile_error!(env, "unable to load step module #{inspect(step_module)}: #{inspect(reason)}")
    end
  end

  defp compile_error!(env, message) do
    raise CompileError,
      file: env.file,
      line: env.line,
      description: message
  end
end

defmodule Hephaestus.Workflow do
  @moduledoc """
  Macro module for defining workflows with callback-based pattern matching.

  Add `use Hephaestus.Workflow` to a module to declare a workflow via
  `start/0` and `transit/3`. Static clauses ignore the context argument
  with `_ctx`. Dynamic clauses use `@targets` before the clause to declare
  possible destinations for DAG validation. The macro extracts the step DAG
  at compile time, validates it with `libgraph`, cross-checks `events/0`
  declarations, and generates `__predecessors__/1` and `__graph__/0` helpers
  for runtime coordination.
  """

  @dynamic_edges_attr :hephaestus_dynamic_edges

  defmacro __using__(_opts) do
    quote do
      @behaviour Hephaestus.Core.Workflow
      Module.register_attribute(__MODULE__, unquote(@dynamic_edges_attr), accumulate: true)
      Module.register_attribute(__MODULE__, :targets, persist: false)
      @on_definition Hephaestus.Workflow
      @before_compile Hephaestus.Workflow
    end
  end

  def __on_definition__(env, _kind, :transit, args, _guards, _body) when length(args) == 3 do
    targets = Module.get_attribute(env.module, :targets)

    if targets do
      # Dynamic clause — @targets declared, body has logic
      Module.delete_attribute(env.module, :targets)

      [from_ast, event_ast, _context_ast] = args
      from = expand_step_module!(from_ast, env, "transit/3 source")
      event = expand_event!(event_ast, env, "transit/3 event")
      expanded_targets = expand_targets!(targets, env, "transit/3 @targets")

      Module.put_attribute(env.module, @dynamic_edges_attr, %{
        from: from,
        event: event,
        targets: expanded_targets,
        dynamic?: true
      })
    end

    # Static clauses (no @targets) are extracted in @before_compile via Module.get_definition
  end

  def __on_definition__(_env, _kind, _name, _args, _guards, _body), do: :ok

  defmacro __before_compile__(env) do
    start = extract_start!(env)
    edges = extract_static_edges!(env) ++ Enum.reverse(Module.get_attribute(env.module, @dynamic_edges_attr) || [])
    %{graph: graph, predecessors: predecessors} = Hephaestus.Core.Workflow.validate!(env.module, start, edges, env)

    graph_ast = Macro.escape(graph)
    predecessors_ast = Macro.escape(predecessors)

    quote do
      def __predecessors__(module), do: Map.get(unquote(predecessors_ast), module, MapSet.new())
      def __graph__, do: unquote(graph_ast)
    end
  end

  defp extract_start!(env) do
    case Module.get_definition(env.module, {:start, 0}) do
      {:v1, :def, _meta, [{_clause_meta, [], [], body}]} ->
        extract_target!(body, env, "start/0")

      nil ->
        raise CompileError,
          file: env.file,
          line: env.line,
          description: "workflow must define start/0"
    end
  end

  defp extract_static_edges!(env) do
    dynamic_edges = Module.get_attribute(env.module, @dynamic_edges_attr) || []
    dynamic_keys = MapSet.new(dynamic_edges, fn %{from: from, event: event} -> {from, event} end)

    case Module.get_definition(env.module, {:transit, 3}) do
      nil ->
        []

      {:v1, :def, _meta, clauses} ->
        clauses
        |> Enum.map(fn {_clause_meta, [from_ast, event_ast, _ctx_ast], _guards, body} ->
          from = expand_step_module!(from_ast, env, "transit/3 source")
          event = expand_event!(event_ast, env, "transit/3 event")

          if MapSet.member?(dynamic_keys, {from, event}) do
            # Dynamic clause — already captured by __on_definition__, skip
            nil
          else
            %{
              from: from,
              event: event,
              targets: extract_targets!(body, env, "transit/3 body"),
              dynamic?: false
            }
          end
        end)
        |> Enum.reject(&is_nil/1)
    end
  end

  defp extract_targets!(body, env, context) do
    case body do
      list when is_list(list) ->
        Enum.map(list, &extract_target!(&1, env, context))

      other ->
        [extract_target!(other, env, context)]
    end
  end

  defp extract_target!({module, _config}, env, _context) when is_atom(module),
    do: maybe_resolve_nested_module(module, module, env)

  defp extract_target!(module, env, _context) when is_atom(module),
    do: maybe_resolve_nested_module(module, module, env)

  defp extract_target!(other, env, context) do
    raise CompileError,
      file: env.file,
      line: env.line,
      description: "#{context} must return step modules, {step_module, config}, or lists of them, got: #{inspect(other)}"
  end

  defp expand_targets!(targets, env, context) when is_list(targets) do
    Enum.map(targets, &expand_step_module!(&1, env, context))
  end

  defp expand_targets!(other, env, context) do
    raise CompileError,
      file: env.file,
      line: env.line,
      description: "#{context} must be a list of step modules, got: #{inspect(other)}"
  end

  defp expand_step_module!(ast, env, context) do
    expanded = Macro.expand(ast, env)
    resolved = maybe_resolve_nested_module(expanded, ast, env)

    if is_atom(resolved) do
      resolved
    else
      raise CompileError,
        file: env.file,
        line: env.line,
        description: "#{context} must be a step module, got: #{Macro.to_string(ast)}"
    end
  end

  defp expand_event!(ast, env, context) do
    expanded = Macro.expand(ast, env)

    if is_atom(expanded) do
      expanded
    else
      raise CompileError,
        file: env.file,
        line: env.line,
        description: "#{context} must be an atom event, got: #{Macro.to_string(ast)}"
    end
  end

  defp maybe_resolve_nested_module(expanded, {:__aliases__, _, segments}, env) when is_atom(expanded) do
    nested = Module.concat(env.module, Module.concat(segments))

    case Code.ensure_compiled(nested) do
      {:module, _module} -> nested
      {:error, _reason} -> expanded
    end
  end

  defp maybe_resolve_nested_module(expanded, _ast, env) when is_atom(expanded) do
    case Module.split(expanded) do
      [single] ->
        nested = Module.concat(env.module, single)

        case Code.ensure_compiled(nested) do
          {:module, _module} -> nested
          {:error, _reason} -> expanded
        end

      _many ->
        expanded
    end
  end

  defp maybe_resolve_nested_module(expanded, _ast, _env), do: expanded
end
