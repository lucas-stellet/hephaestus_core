defmodule Mix.Tasks.Hephaestus.Gen.Docs do
  @shortdoc "Generates @moduledoc with ASCII execution graph for all Hephaestus workflows"

  @moduledoc """
  Generates `@moduledoc` documentation with an ASCII flowchart showing
  all possible execution paths for every module that uses `Hephaestus.Workflow`.

      $ mix hephaestus.gen.docs

  The task compiles the project, discovers workflow modules via the
  `__graph__/0` function injected by the macro, and updates each source
  file with an ASCII diagram rendered top-to-bottom.

  Re-running the task is idempotent — it replaces the previously generated
  section between HTML comment markers.
  """

  use Mix.Task

  @doc_marker_start "<!-- hephaestus:graph:start -->"
  @doc_marker_end "<!-- hephaestus:graph:end -->"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("compile", [])

    workflows = discover_workflows()

    if workflows == [] do
      Mix.shell().info("No Hephaestus workflows found.")
    else
      workflows
      |> Enum.group_by(&find_source_file/1)
      |> Enum.reject(fn {path, _} -> is_nil(path) end)
      |> Enum.each(&update_file/1)

      Mix.shell().info("Updated #{length(workflows)} workflow(s).")
    end
  end

  # -- Discovery --

  defp discover_workflows do
    compile_paths()
    |> Enum.flat_map(&beam_modules/1)
    |> Enum.filter(&workflow_module?/1)
    |> Enum.sort()
  end

  defp compile_paths do
    [Mix.Project.compile_path()]
    |> Enum.filter(&File.dir?/1)
    |> Enum.uniq()
  end

  defp beam_modules(dir) do
    dir
    |> Path.join("*.beam")
    |> Path.wildcard()
    |> Enum.map(fn beam_path ->
      beam_path
      |> Path.basename(".beam")
      |> String.to_atom()
      |> then(fn mod_atom ->
        case :code.ensure_loaded(mod_atom) do
          {:module, mod} -> mod
          _ -> nil
        end
      end)
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp workflow_module?(module) do
    function_exported?(module, :__graph__, 0) and
      function_exported?(module, :__edges__, 0) and
      function_exported?(module, :start, 0)
  end

  defp find_source_file(module) do
    case module.module_info(:compile)[:source] do
      nil -> nil
      charlist -> to_string(charlist)
    end
  end

  # -- File update (handles multiple modules per file) --

  defp update_file({path, modules}) do
    source = File.read!(path)
    new_source = Enum.reduce(modules, source, &inject_for_module/2)

    if new_source != source do
      File.write!(path, new_source)
    end

    Enum.each(modules, fn mod ->
      Mix.shell().info("  updated #{inspect(mod)} in #{path}")
    end)
  end

  defp inject_for_module(module, source) do
    module_name = inspect(module)
    ascii = build_ascii_graph(module)

    doc_block =
      "#{@doc_marker_start}\n" <>
        "  ## Execution Graph\n\n" <>
        ascii <>
        "\n  #{@doc_marker_end}"

    marker_id = marker_for(module_name)

    cond do
      String.contains?(source, marker_id) ->
        replace_existing_block(source, module_name, doc_block)

      has_moduledoc_in_defmodule?(source, module_name) ->
        append_to_existing_moduledoc(source, module_name, doc_block)

      true ->
        inject_new_moduledoc(source, module_name, doc_block)
    end
  end

  defp marker_for(module_name) do
    "<!-- hephaestus:graph:start:#{module_name} -->"
  end

  defp marker_end_for(module_name) do
    "<!-- hephaestus:graph:end:#{module_name} -->"
  end

  # -- ASCII graph generation --

  defp build_ascii_graph(module) do
    graph = module.__graph__()
    edges = module.__edges__()
    start_mod = normalize_start(module.start())

    # Build edge lookup: {from, target} -> event
    edge_labels = build_edge_labels(edges)

    # Assign layers via longest path from start
    layers = assign_layers(graph, start_mod)

    # Group nodes by layer
    layer_groups =
      layers
      |> Enum.group_by(fn {_mod, layer} -> layer end, fn {mod, _layer} -> mod end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {_layer, mods} -> Enum.sort_by(mods, &short_name/1) end)

    # Render layers top-to-bottom
    render_layers(layer_groups, graph, edge_labels, start_mod)
  end

  defp build_edge_labels(edges) do
    Enum.reduce(edges, %{}, fn %{from: from, event: event, targets: targets}, acc ->
      Enum.reduce(targets, acc, fn target, inner_acc ->
        Map.put(inner_acc, {from, target}, event)
      end)
    end)
  end

  defp assign_layers(graph, start_mod) do
    # Longest path from start to each node (ensures fan-in nodes appear after all predecessors)
    topo = Graph.topsort(graph)

    Enum.reduce(topo, %{}, fn node, distances ->
      if node == start_mod do
        Map.put(distances, node, 0)
      else
        preds = Graph.in_neighbors(graph, node)

        max_pred =
          preds
          |> Enum.map(&Map.get(distances, &1, 0))
          |> Enum.max(fn -> 0 end)

        Map.put(distances, node, max_pred + 1)
      end
    end)
  end

  defp render_layers(layer_groups, graph, edge_labels, start_mod) do
    layer_groups
    |> Enum.with_index()
    |> Enum.flat_map(fn {nodes, idx} ->
      node_row = render_node_row(nodes, start_mod)

      if idx < length(layer_groups) - 1 do
        next_nodes = Enum.at(layer_groups, idx + 1)
        connectors = render_connectors(nodes, next_nodes, graph, edge_labels)
        [node_row] ++ connectors
      else
        [node_row]
      end
    end)
    |> Enum.map(&"  #{&1}")
    |> Enum.join("\n")
  end

  defp render_node_row(nodes, start_mod) do
    nodes
    |> Enum.map(fn mod ->
      name = short_name(mod)

      cond do
        mod == Hephaestus.Steps.Done -> "(#{name})"
        mod == start_mod -> "[*#{name}]"
        true -> "[#{name}]"
      end
    end)
    |> Enum.join("    ")
  end

  defp render_connectors(from_nodes, to_nodes, graph, edge_labels) do
    # Collect all edges from this layer to the next
    connections =
      Enum.flat_map(from_nodes, fn from ->
        graph
        |> Graph.out_neighbors(from)
        |> Enum.filter(&(&1 in to_nodes))
        |> Enum.map(fn to ->
          event = Map.get(edge_labels, {from, to}, :"?")
          {from, to, event}
        end)
      end)

    if connections == [] do
      []
    else
      # Build labeled arrows
      lines =
        connections
        |> Enum.map(fn {from, to, event} ->
          from_name = short_name(from)
          to_name = short_name(to)

          if from_name == to_name do
            "  │ :#{event}"
          else
            "  #{from_name} ──:#{event}──> #{to_name}"
          end
        end)

      # Add a pipe separator
      ["  │"] ++ lines ++ ["  │"]
    end
  end

  defp short_name(module) do
    module |> Module.split() |> List.last()
  end

  defp normalize_start(module) when is_atom(module), do: module
  defp normalize_start({module, _config}) when is_atom(module), do: module

  # -- Source file manipulation --

  defp replace_existing_block(source, module_name, doc_block) do
    start_marker = marker_for(module_name)
    end_marker = marker_end_for(module_name)

    tagged_block = tag_block(doc_block, module_name)

    pattern = ~r/#{Regex.escape(start_marker)}.*?#{Regex.escape(end_marker)}/s
    Regex.replace(pattern, source, tagged_block)
  end

  defp has_moduledoc_in_defmodule?(source, module_name) do
    defmodule_pattern = defmodule_regex(module_name)

    case Regex.run(defmodule_pattern, source) do
      nil -> false
      [match] -> String.contains?(match, "@moduledoc")
    end
  end

  defp append_to_existing_moduledoc(source, module_name, doc_block) do
    tagged_block = tag_block(doc_block, module_name)

    defmod_start = "defmodule #{module_name} do"

    case :binary.match(source, defmod_start) do
      :nomatch ->
        source

      {pos, len} ->
        after_defmod = binary_part(source, pos + len, byte_size(source) - pos - len)

        case Regex.run(~r/(.*?@moduledoc\s+\"\"\"\n)(.*?)(\"\"\")/s, after_defmod,
               return: :index
             ) do
          [{_full_start, _full_len}, _g1, _g2, {close_start, _close_len}] ->
            insert_pos = pos + len + close_start
            before_close = binary_part(source, 0, insert_pos)
            after_close = binary_part(source, insert_pos, byte_size(source) - insert_pos)
            before_close <> "\n  #{tagged_block}\n  " <> after_close

          _ ->
            source
        end
    end
  end

  defp inject_new_moduledoc(source, module_name, doc_block) do
    tagged_block = tag_block(doc_block, module_name)
    defmod_line = "defmodule #{module_name} do"
    use_line = "use Hephaestus.Workflow"

    case :binary.match(source, defmod_line) do
      :nomatch ->
        source

      {defmod_pos, defmod_len} ->
        after_defmod =
          binary_part(
            source,
            defmod_pos + defmod_len,
            byte_size(source) - defmod_pos - defmod_len
          )

        case :binary.match(after_defmod, use_line) do
          :nomatch ->
            source

          {use_rel_pos, use_len} ->
            use_abs_end = defmod_pos + defmod_len + use_rel_pos + use_len
            before = binary_part(source, 0, use_abs_end)
            after_use = binary_part(source, use_abs_end, byte_size(source) - use_abs_end)

            moduledoc =
              "\n\n  @moduledoc \"\"\"\n" <>
                "  Workflow `#{module_name}`.\n\n" <>
                "  #{tagged_block}\n" <>
                "  \"\"\""

            before <> moduledoc <> after_use
        end
    end
  end

  defp tag_block(doc_block, module_name) do
    doc_block
    |> String.replace(@doc_marker_start, marker_for(module_name))
    |> String.replace(@doc_marker_end, marker_end_for(module_name))
  end

  defp defmodule_regex(module_name) do
    escaped = Regex.escape(module_name)
    ~r/defmodule\s+#{escaped}\s+do\b.*?(?=\ndefmodule\s|\z)/s
  end
end
