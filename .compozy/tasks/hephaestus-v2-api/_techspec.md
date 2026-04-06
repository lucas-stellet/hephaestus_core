# TechSpec: Hephaestus v2 API

## Executive Summary

Hephaestus v2 API substitui a definicao de workflows baseada em structs (`definition/0` -> `%Workflow{steps: [%Step{}]}`) por callbacks com pattern matching idiomatico: `start/0` (step inicial), `transit/2` (roteamento estatico), e opcionalmente `transit/3` + `@targets` (roteamento dinamico). Steps declaram `events/0` (atoms), permitindo validacao cruzada completa em compile-time. DAG construido e validado via `libgraph`. Breaking change — versao 0.2.0.

Trade-offs: perde-se o `StepDefinition` protocol (extensibilidade por libs externas via structs customizadas) em troca de uma API mais idiomatica e validacao estatica mais forte. O macro `use Hephaestus.Workflow` ganha complexidade significativa (interceptacao de `def transit`, acumulo de edges via `Module.register_attribute`, cross-validation com `events/0`) mas isso e complexidade concentrada num unico ponto — o resto do sistema simplifica.

## System Architecture

### Component Overview

```
┌─────────────────────────────────────────────────────────┐
│  MyApp.Hephaestus (use Hephaestus)                      │
│  Supervision tree: Registry + DynamicSup + TaskSup + ETS│
│  API: start_instance/2, resume/2                        │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌─────────────────────┐    ┌────────────────────────┐  │
│  │  Runtime             │    │  Storage               │  │
│  │  Runner (behaviour)  │    │  Storage (behaviour)   │  │
│  │  └─ Runner.Local     │◄──►│  └─ Storage.ETS       │  │
│  │     (GenServer +     │    │                        │  │
│  │      DynamicSup +    │    └────────────────────────┘  │
│  │      TaskSup)        │                                │
│  └──────────┬───────────┘                                │
│             │ delega                                     │
│  ┌──────────▼───────────┐                                │
│  │  Core (puro)          │    ┌────────────────────────┐ │
│  │  Engine.advance/1     │◄───│  Workflow (macro)       │ │
│  │  Engine.execute_step  │    │  start/0               │ │
│  │  Engine.complete_step │    │  transit/2, transit/3   │ │
│  │  Engine.resume        │    │  events/0 (nos steps)  │ │
│  │  Engine.resolve_transit│   │  @before_compile:      │ │
│  │                       │    │    edge extraction      │ │
│  │  Instance (struct)    │    │    libgraph DAG valid.  │ │
│  │  Context (struct)     │    │    events × transit     │ │
│  │  ExecutionEntry       │    │    context key collision│ │
│  └───────────────────────┘    └────────────────────────┘ │
│                                                         │
│  ┌─────────────────────┐    ┌────────────────────────┐  │
│  │  Steps               │    │  Connectors            │  │
│  │  Step (behaviour)    │    │  Connector (behaviour) │  │
│  │  ├─ Wait             │    │  (sem implementacoes)  │  │
│  │  ├─ WaitForEvent     │    └────────────────────────┘  │
│  │  ├─ End              │                                │
│  │  └─ Debug            │                                │
│  └─────────────────────┘                                 │
└─────────────────────────────────────────────────────────┘

REMOVIDOS da v1:
  ✗ %Workflow{} struct (substituido por callbacks)
  ✗ %Step{} struct (modulo = identidade)
  ✗ StepDefinition protocol (sem indirecao)
  ✗ definition/0 callback
```

**Mudancas chave vs v1:**
- `Workflow (macro)` substitui `Workflow (callbacks)` — nao ha mais `definition/0` retornando struct. O macro intercepta `def transit` e acumula edges
- Engine ganha `resolve_transit/3` — chama `workflow.transit(from, event)` diretamente em vez de navegar via `StepDefinition.transitions()`
- `__step__/1` e `__predecessors__/1` continuam gerados pelo `@before_compile`, mas agora derivados das edges acumuladas pelo macro (nao mais da struct)
- `__steps_map__/0` removido — nao ha mais map de `ref => %Step{}`
- Steps identificados por modulo (atom), nao mais por ref atom separado
- Bloco `Connectors` inalterado — fora de escopo

### Directory Structure (pos-v2)

```
lib/hephaestus/
  core/
    engine.ex            # + resolve_transit/3, events como atoms
    instance.ex          # + step_configs field
    context.ex           # keys como snake_case atoms de modulos
    workflow.ex          # REWRITE: macro com edge extraction + libgraph
    execution_entry.ex   # event type: atom()
    step.ex              # REMOVIDO
    step_definition.ex   # REMOVIDO
  runtime/
    runner.ex            # event type: atom()
    runner/local.ex      # adapta pra novo engine API
    storage.ex           # inalterado
    storage/ets.ex       # inalterado
  steps/
    step.ex              # + events/0 callback, event type: atom()
    wait.ex              # + events/0
    wait_for_event.ex    # + events/0
    end_step.ex          # + events/0, retorna :end
    debug.ex             # + events/0, retorna :completed atom
  connectors/
    connector.ex         # inalterado
  hephaestus.ex          # event type: atom() no resume
```

### Data Flow

1. App chama `MyApp.Hephaestus.start_instance(OrderWorkflow, %{items: items})`
2. Modulo de entrada delega pro Runner configurado
3. Runner cria `Instance.new(workflow, context)`, persiste no Storage
4. Runner.Local starta GenServer via DynamicSupervisor
5. GenServer chama `Engine.advance(instance)` — core puro
6. Engine chama `workflow.start()` pra obter step inicial, ativa-o
7. GenServer executa step via `Engine.execute_step(instance, step_module)`
8. Engine busca config de `instance.step_configs`, chama `step_module.execute(instance, config, context)`
9. Step retorna `{:ok, event_atom, context_updates}`
10. Engine chama `Engine.complete_step` — grava resultado em `context.steps.<snake_case_key>`
11. Engine chama `Engine.activate_transitions` — resolve `workflow.transit(from_module, event)` pra obter proximo(s) step(s)
12. Em fan-out, GenServer usa TaskSupervisor pra paralelismo real
13. Em wait/wait_for_event, GenServer pausa e espera resume com event atom

## Implementation Design

### Core Interfaces

**Workflow Callbacks**
```elixir
@callback start() :: module() | {module(), config :: map() | struct()}

@callback transit(from :: module(), event :: atom()) ::
  module()
  | {module(), config :: map() | struct()}
  | [module() | {module(), config :: map() | struct()}]

# Opcional — requer @targets antes da clause
@callback transit(from :: module(), event :: atom(), context :: Context.t()) ::
  module()
  | {module(), config :: map() | struct()}
  | [module() | {module(), config :: map() | struct()}]
```

`transit` nunca retorna `:end`. Step terminal e `Hephaestus.Steps.End` — o unico leaf node valido no DAG. Todo caminho deve terminar nele (decisao ADR-003).

**Step Behaviour**
```elixir
defmodule Hephaestus.Steps.Step do
  @callback events() :: [atom()]
  @callback execute(Instance.t(), config :: map() | nil, Context.t()) ::
    {:ok, atom()}
    | {:ok, atom(), map()}
    | {:async}
    | {:error, term()}

  # Opcional — override da context key derivada
  @callback step_key() :: atom()

  @optional_callbacks [step_key: 0]
end
```

`events/0` e obrigatorio. Retorna lista de atoms. Validado em compile-time contra as clauses do transit.

**Engine — funcoes puras**
```elixir
defmodule Hephaestus.Core.Engine do
  @spec advance(Instance.t()) :: {:ok, Instance.t()} | {:error, term()}
  @spec execute_step(Instance.t(), module()) ::
    {:ok, atom()} | {:ok, atom(), map()} | {:async} | {:error, term()}
  @spec complete_step(Instance.t(), module(), atom(), map()) :: Instance.t()
  @spec activate_transitions(Instance.t(), module(), atom()) :: Instance.t()
  @spec check_completion(Instance.t()) :: Instance.t()
  @spec resume_step(Instance.t(), module(), atom()) :: Instance.t()
end
```

Mudancas vs v1:
- `execute_step/2` recebe `module()` direto em vez de `step_def` (sem `StepDefinition` protocol)
- `complete_step/4` — `step_ref` muda de `atom()` (ref arbitrario) para `module()` (o proprio step)
- `activate_transitions/3` — chama `workflow.transit(from_module, event)` diretamente em vez de navegar `StepDefinition.transitions()`
- `resume_step/3` — event muda de `String.t()` para `atom()`
- Validacao runtime: `execute_step` checa `function_exported?(module, :execute, 3)` antes de chamar (decisao 8 do design doc)

**Runner Behaviour** — mesma interface, event type muda:
```elixir
@callback start_instance(module(), map(), keyword()) ::
  {:ok, String.t()} | {:error, term()}
@callback resume(String.t(), atom()) :: :ok | {:error, term()}
@callback schedule_resume(String.t(), module(), pos_integer()) ::
  {:ok, reference()} | {:error, term()}
```

**Storage e Connector** — inalterados.

### Core Interfaces — Exemplos de Codigo

**Workflow com transit/2 estatico:**
```elixir
defmodule Pedidox.Workflows.OrderWorkflow do
  use Hephaestus.Workflow

  @impl true
  def start, do: Steps.ValidateOrder

  @impl true
  def transit(Steps.ValidateOrder, :valid), do: Steps.CalculateTotal
  def transit(Steps.CalculateTotal, :high_value), do: [Steps.CheckInventory, Steps.CheckFraud]
  def transit(Steps.CalculateTotal, :low_value), do: Steps.WaitForPayment
  def transit(Steps.CheckInventory, :done), do: Steps.WaitForPayment
  def transit(Steps.CheckFraud, :done), do: Steps.WaitForPayment
  def transit(Steps.WaitForPayment, :payment_confirmed), do: Steps.ConfirmOrder
  def transit(Steps.ConfirmOrder, :confirmed), do: Hephaestus.Steps.End
end
```

**Workflow com transit/3 dinamico + @targets:**
```elixir
defmodule MyApp.Workflows.ShippingFlow do
  use Hephaestus.Workflow

  @impl true
  def start, do: Steps.ReceiveOrder

  @impl true
  def transit(Steps.ReceiveOrder, :received), do: Steps.CalculateShipping

  @targets [Steps.StandardShipping, Steps.ExpressShipping, Steps.InStorePickup]
  def transit(Steps.CalculateShipping, :calculated, ctx) do
    case ctx.steps.calculate_shipping.method do
      :standard -> Steps.StandardShipping
      :express -> {Steps.ExpressShipping, %{priority: :high}}
      :pickup -> Steps.InStorePickup
    end
  end

  def transit(Steps.StandardShipping, :shipped), do: Hephaestus.Steps.End
  def transit(Steps.ExpressShipping, :shipped), do: Hephaestus.Steps.End
  def transit(Steps.InStorePickup, :ready), do: Hephaestus.Steps.End
end
```

**Step com events/0:**
```elixir
defmodule Steps.CalculateTotal do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:high_value, :low_value]

  @impl true
  def execute(_instance, _config, context) do
    total = Enum.sum(Enum.map(context.initial.items, & &1.price))
    if total > 100 do
      {:ok, :high_value, %{total: total}}
    else
      {:ok, :low_value, %{total: total}}
    end
  end
end
```

**Step com step_key/0 override:**
```elixir
defmodule MyApp.Orders.Steps.Validate do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def step_key, do: :validate_order

  @impl true
  def events, do: [:valid, :invalid]

  @impl true
  def execute(_instance, _config, context) do
    if context.initial[:items] do
      {:ok, :valid, %{item_count: length(context.initial.items)}}
    else
      {:ok, :invalid}
    end
  end
end
```

**Engine — execute_step com validacao runtime (decisao 8):**
```elixir
def execute_step(%Instance{} = instance, step_module) when is_atom(step_module) do
  unless function_exported?(step_module, :execute, 3) do
    raise "#{inspect(step_module)} must implement execute/3"
  end

  config = Map.get(instance.step_configs, step_module)
  step_module.execute(instance, config, instance.context)
end
```

**Engine — activate_transitions chamando transit diretamente:**
```elixir
def activate_transitions(%Instance{} = instance, from_module, event) do
  case resolve_transit(instance.workflow, from_module, event) do
    nil -> instance
    target when is_atom(target) -> maybe_activate_step(instance, target, nil)
    {target, config} -> maybe_activate_step(acc, target, config)
    targets when is_list(targets) ->
      Enum.reduce(targets, instance, fn
        {mod, cfg}, acc -> maybe_activate_step(acc, mod, cfg)
        mod, acc -> maybe_activate_step(acc, mod, nil)
      end)
  end
end

defp resolve_transit(workflow, from, event) do
  cond do
    function_exported?(workflow, :transit, 3) ->
      # tenta transit/3 primeiro, fallback pra transit/2
      # ...
    true ->
      workflow.transit(from, event)
  end
end
```

**Built-in End com events/0 (decisao 17):**
```elixir
defmodule Hephaestus.Steps.End do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:end]

  @impl true
  def execute(_instance, _config, _context), do: {:ok, :end}
end
```

**Acesso a context com snake_case keys (decisao 7):**
```elixir
# Dentro de um step:
def execute(_instance, _config, context) do
  # Steps.ValidateOrder -> :validate_order
  item_count = context.steps.validate_order.item_count

  # Steps.CalculateTotal -> :calculate_total
  total = context.steps.calculate_total.total

  {:ok, :done, %{summary: "#{item_count} items, $#{total}"}}
end
```

### Data Models

**Instance — novo campo `step_configs`**
```elixir
defmodule Hephaestus.Core.Instance do
  @enforce_keys [:id, :workflow]
  defstruct [
    :id,
    :workflow,
    :current_step,
    status: :pending,
    context: %Context{initial: %{}, steps: %{}},
    active_steps: MapSet.new(),
    completed_steps: MapSet.new(),
    execution_history: [],
    step_configs: %{}            # NOVO — module => config
  ]

  @type t :: %__MODULE__{
    id: String.t(),
    workflow: module(),
    current_step: module() | nil,       # era atom() (ref), agora module()
    status: status(),
    context: Context.t(),
    active_steps: MapSet.t(module()),    # era MapSet.t(atom()), agora module()
    completed_steps: MapSet.t(module()), # idem
    execution_history: list(),
    step_configs: %{optional(module()) => map() | struct()}
  }
end
```

`step_configs` e populado quando `transit` retorna `{module, config}`. O engine guarda `Map.put(step_configs, module, config)` ao ativar o step, passa como segundo argumento ao `execute/3`, e remove ao completar (decisao 10 do design doc).

**Exemplo de step_configs flow:**
```elixir
# transit retorna tupla com config
def transit(Steps.Process, :ready), do: {Steps.WaitForPayment, %WaitConfig{event_name: "payment"}}

# Engine ao ativar step:
instance = %{instance |
  active_steps: MapSet.put(instance.active_steps, Steps.WaitForPayment),
  step_configs: Map.put(instance.step_configs, Steps.WaitForPayment, %WaitConfig{...})
}

# Engine ao executar:
config = Map.get(instance.step_configs, step_module)  # %WaitConfig{...} ou nil
step_module.execute(instance, config, instance.context)

# Engine ao completar step:
instance = %{instance |
  active_steps: MapSet.delete(instance.active_steps, step_module),
  completed_steps: MapSet.put(instance.completed_steps, step_module),
  step_configs: Map.delete(instance.step_configs, step_module)
}
```

**Context — keys como snake_case atoms de modulos**

Struct nao muda — continua `%Context{initial: map(), steps: map()}`. O que muda e a key usada em `put_step_result`:

```elixir
# v1: atom ref arbitrario
Context.put_step_result(context, :validate, %{valid: true})
context.steps.validate.valid

# v2: snake_case do ultimo segmento do modulo
Context.put_step_result(context, :validate_order, %{valid: true})
context.steps.validate_order.valid
```

A conversao `Steps.ValidateOrder -> :validate_order` e feita pelo engine (nao pelo Context). Se o step implementa `step_key/0`, usa o override.

**Conversao module -> context key:**
```elixir
defp module_to_context_key(module) do
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

# Steps.ValidateOrder  -> :validate_order
# Steps.CheckFraud     -> :check_fraud
```

**ExecutionEntry — event type muda**
```elixir
defmodule Hephaestus.Core.ExecutionEntry do
  @enforce_keys [:step_ref, :event, :timestamp]
  defstruct [:step_ref, :event, :timestamp, :context_updates]

  @type t :: %__MODULE__{
    step_ref: module(),     # era atom() (ref), agora module()
    event: atom(),          # era String.t(), agora atom()
    timestamp: DateTime.t(),
    context_updates: map() | nil
  }
end
```

**Structs removidas:**
- `%Hephaestus.Core.Workflow{}` — nao existe mais. Workflow e um modulo com callbacks
- `%Hephaestus.Core.Step{}` — modulo = identidade. Sem struct intermediaria

## Compile-time Validation & Macro Internals

### Como `use Hephaestus.Workflow` funciona

O macro faz 3 coisas:
1. Registra o behaviour e o `@before_compile`
2. Intercepta `def transit` via `__on_definition__` callback pra acumular edges de transit/3
3. No `@before_compile`, extrai edges de transit/2 via `Module.get_definition/2`, merge com edges dinamicas, constroi o DAG com `libgraph` e valida tudo

### Passo 1 — Setup do macro

```elixir
defmacro __using__(_opts) do
  quote do
    @behaviour Hephaestus.Core.Workflow
    Module.register_attribute(__MODULE__, :hephaestus_dynamic_edges, accumulate: true)
    Module.register_attribute(__MODULE__, :targets, accumulate: false)
    @on_definition Hephaestus.Workflow
    @before_compile Hephaestus.Workflow
  end
end
```

### Passo 2 — `__on_definition__` captura @targets de transit/3

Quando o compilador encontra cada `def transit/3`, o callback le `@targets` e acumula:

```elixir
def __on_definition__(env, :def, :transit, args, _guards, _body) do
  case args do
    # transit/3 — requer @targets
    [from_ast, event_ast, _ctx] ->
      targets = Module.get_attribute(env.module, :targets)

      unless targets do
        raise CompileError,
          file: env.file, line: env.line,
          description: "transit/3 clause requires @targets annotation"
      end

      from = Macro.expand(from_ast, env)
      event = Macro.expand(event_ast, env)

      Module.put_attribute(env.module, :hephaestus_dynamic_edges,
        %{from: from, event: event, targets: targets, type: :dynamic})
      Module.put_attribute(env.module, :targets, nil)

    # transit/2 — ignorado aqui, extraido no @before_compile
    _ -> :ok
  end
end
```

### Passo 3 — `@before_compile` extrai transit/2 + valida tudo

```elixir
defmacro __before_compile__(env) do
  # 1. Extrair edges estaticas de transit/2 via Module.get_definition
  static_edges = extract_transit2_edges(env)

  # 2. Ler edges dinamicas acumuladas pelo __on_definition__
  dynamic_edges = Module.get_attribute(env.module, :hephaestus_dynamic_edges)

  # 3. Obter start module
  start_module = extract_start_module(env)

  # 4. Coletar todos os step modules do grafo
  all_modules = collect_all_modules(start_module, static_edges, dynamic_edges)

  # 5. Construir DAG via libgraph
  graph = build_graph(start_module, static_edges, dynamic_edges)

  # 6. Validacoes
  validate_acyclic!(graph, env)
  validate_reachable!(graph, start_module, env)
  validate_fan_out_convergence!(graph, static_edges, dynamic_edges, env)
  validate_leaf_nodes_are_end!(graph, env)
  validate_events_cross_reference!(static_edges, dynamic_edges, all_modules, env)
  validate_context_keys!(all_modules, env)
  validate_events_are_atoms!(all_modules, env)

  # 7. Computar predecessors pra fan-in
  predecessors = compute_predecessors(graph)

  # 8. Gerar funcoes auxiliares
  quote do
    def __predecessors__(module), do: Map.get(unquote(predecessors_ast), module, MapSet.new())
    def __graph__, do: unquote(graph_ast)
  end
end
```

### Extracao de edges de transit/2

```elixir
defp extract_transit2_edges(env) do
  case Module.get_definition(env.module, {:transit, 2}) do
    nil -> []
    {:v1, :def, _meta, clauses} ->
      Enum.map(clauses, fn {_clause_meta, [from, event], _guards, body} ->
        targets = extract_targets_from_body(body)
        %{from: from, event: event, targets: targets, type: :static}
      end)
  end
end

defp extract_targets_from_body(body) do
  case body do
    # Modulo direto
    module when is_atom(module) -> [module]
    # Tupla {module, config}
    {module, _config} when is_atom(module) -> [module]
    # Lista (fan-out)
    targets when is_list(targets) ->
      Enum.map(targets, fn
        {mod, _cfg} when is_atom(mod) -> mod
        mod when is_atom(mod) -> mod
      end)
  end
end
```

### Tabela de validacoes

| Validacao | Input | Erro |
|-----------|-------|------|
| Evento sem transit | `events/0` retorna `:out_of_stock` mas nenhum `transit(Mod, :out_of_stock)` existe | `Steps.CheckInventory declares event :out_of_stock but no transit handles it` |
| Transit sem evento | `transit(Mod, :timeout)` existe mas `:timeout` nao esta em `events/0` | `transit handles (Steps.CheckInventory, :timeout) but step does not declare :timeout in events/0` |
| Fan-out sem join | `transit(A, :x)` retorna `[B, C]` e B->End sem convergir | `Branch Steps.B from fan-out at Steps.A terminates without joining` |
| transit/3 sem @targets | `def transit(Mod, :ev, ctx)` sem `@targets` antes | `transit/3 clause for (Mod, :ev) requires @targets annotation` |
| Colisao de context keys | `MyApp.Steps.Validate` e `Other.Steps.Validate` -> ambos `:validate` | `Context key collision: ... both resolve to :validate. Use step_key/0 to override` |
| Ciclo no DAG | A->B->C->A | `Cycle detected: A -> B -> C -> A` |
| Steps orfaos | Step D nao alcancavel a partir de `start/0` | `Unreachable step: Steps.D` |
| Eventos nao-atom | `def events, do: ["done"]` | `Events must be atoms, got "done" in Steps.X` |
| Leaf node != End | Caminho termina em Steps.ConfirmOrder | `Path terminates at Steps.ConfirmOrder which is not Hephaestus.Steps.End. All workflow paths must end with Hephaestus.Steps.End` |

### Step terminal

Todo caminho do DAG DEVE terminar em `Hephaestus.Steps.End` (ADR-003). Validacao:

```elixir
defp validate_leaf_nodes_are_end!(graph, env) do
  leaf_nodes = Graph.vertices(graph) |> Enum.filter(&(Graph.out_degree(graph, &1) == 0))

  Enum.each(leaf_nodes, fn node ->
    unless node == Hephaestus.Steps.End do
      compile_error!(env,
        "Path terminates at #{inspect(node)} which is not Hephaestus.Steps.End. " <>
        "All workflow paths must end with Hephaestus.Steps.End")
    end
  end)
end
```

Regra de `events/0` x transit:
- Para `Hephaestus.Steps.End`: `events/0` retorna `[:end]`, sem transit necessario — validacao pula este modulo
- Para qualquer outro step: TODO evento em `events/0` DEVE ter transit correspondente

## API Endpoints

N/A — Hephaestus e uma lib Elixir, nao expoe HTTP endpoints. A API publica e programatica via `use Hephaestus`.

## Integration Points

N/A — lib Elixir pura, sem dependencias de Phoenix, Ecto, ou servicos externos. Unica dependencia nova: `libgraph` (hex package) para validacao de DAG em compile-time.

## Impact Analysis

| Arquivo | Impacto | Descricao e Risco | Acao |
|---------|---------|-------------------|------|
| `lib/hephaestus.ex` | modificado | `resume/2` — event type `String.t()` -> `atom()`. Guard `is_binary(event)` -> `is_atom(event)` | Alterar guard e typespec |
| `lib/hephaestus/core/engine.ex` | modificado | Remove dependencia de `StepDefinition` protocol. `execute_step/2` recebe `module()` direto e busca config de `instance.step_configs`. `activate_transitions/3` chama `workflow.transit(from, event)` via `resolve_transit/3` (nova funcao). `complete_step/4` e `resume_step/3` — step_ref muda de `atom()` para `module()`, event de `String.t()` para `atom()`. `ensure_started/1` chama `workflow.start()` em vez de `workflow.definition().initial_step`. Remove `__step__/1` e `StepDefinition` calls | Reescrever funcoes mantendo mesma estrutura |
| `lib/hephaestus/core/instance.ex` | modificado | Adiciona campo `step_configs: %{}`. Types de `active_steps`, `completed_steps`, `current_step` mudam de `atom()` para `module()` | Adicionar campo e atualizar types |
| `lib/hephaestus/core/context.ex` | inalterado | Struct e funcoes nao mudam. A conversao module->snake_case key e responsabilidade do engine, nao do Context | Nenhuma |
| `lib/hephaestus/core/workflow.ex` | reescrita total | Remove `%Workflow{}` struct e `definition/0`. Implementa novo macro: `__using__` com register_attribute + `@on_definition` + `@before_compile`. `__on_definition__` captura `@targets` de transit/3. `__before_compile__` extrai edges de transit/2 via `Module.get_definition/2`, merge com dynamic edges, constroi DAG via `libgraph`, valida tudo (ciclos, orphans, fan-out convergence, events x transit, context key collision, leaf nodes = End). Gera `__predecessors__/1` e `__graph__/0` | Reescrever do zero |
| `lib/hephaestus/core/step.ex` | removido | `%Step{}` struct e `StepDefinition` impl eliminados. Modulo = identidade | Deletar arquivo |
| `lib/hephaestus/core/step_definition.ex` | removido | Protocol eliminado. Engine acessa step modules diretamente | Deletar arquivo |
| `lib/hephaestus/core/execution_entry.ex` | modificado | `step_ref` type: `atom()` -> `module()`. `event` type: `String.t()` -> `atom()` | Atualizar types |
| `lib/hephaestus/steps/step.ex` | modificado | Adiciona `@callback events() :: [atom()]` (obrigatorio) e `@callback step_key() :: atom()` (opcional). `event` type muda de `String.t()` para `atom()` nos returns | Adicionar callbacks e atualizar types |
| `lib/hephaestus/steps/wait.ex` | modificado | Adiciona `def events, do: [:timeout]`. Return `{:async}` nao muda | Adicionar `events/0` |
| `lib/hephaestus/steps/wait_for_event.ex` | modificado | Adiciona `def events, do: [:received]`. Return `{:async}` nao muda | Adicionar `events/0` |
| `lib/hephaestus/steps/end_step.ex` | modificado | Adiciona `def events, do: [:end]`. Return muda de `{:ok, "completed"}` para `{:ok, :end}` | Adicionar `events/0`, evento como atom |
| `lib/hephaestus/steps/debug.ex` | modificado | Adiciona `def events, do: [:completed]`. Return muda de `{:ok, "completed"}` para `{:ok, :completed}` | Adicionar `events/0`, evento como atom |
| `lib/hephaestus/runtime/runner.ex` | modificado | `resume/2` — event type: `String.t()` -> `atom()`. `schedule_resume/3` — step_ref type: `atom()` -> `module()` | Atualizar typespecs |
| `lib/hephaestus/runtime/runner/local.ex` | modificado | `execute_step/2` privado chama `Engine.execute_step(instance, step_module)` direto em vez de buscar via `__step__` + protocol. `handle_cast({:resume, event})` — event agora atom. `handle_info({:scheduled_resume, step_ref})` — event `"timeout"` -> `:timeout` | Adaptar chamadas ao novo Engine |
| `lib/hephaestus/runtime/storage.ex` | inalterado | Interface nao depende de events ou step identity | Nenhuma |
| `lib/hephaestus/runtime/storage/ets.ex` | inalterado | Persiste `Instance.t()` opaco — absorve mudancas automaticamente | Nenhuma |
| `lib/hephaestus/connectors/connector.ex` | inalterado | Fora de escopo | Nenhuma |

**Resumo:** 2 removidos, 1 reescrita total, 10 modificados, 4 inalterados.

## Testing Approach

### Unit Tests (Core puro — sem processos OTP)

Todos testaveis em IEx, sem supervision tree.

**Compile-time validation (`Hephaestus.Workflow` macro):**
- Workflow valido compila sem erros — linear, branch, fan-out com join
- Evento declarado em `events/0` sem transit correspondente -> `CompileError`
- Transit referencia evento nao declarado em `events/0` -> `CompileError`
- `transit/3` sem `@targets` -> `CompileError`
- Ciclo no DAG -> `CompileError`
- Step orfao (nao alcancavel de `start/0`) -> `CompileError`
- Fan-out sem convergencia antes de End -> `CompileError`
- Leaf node que nao e `Hephaestus.Steps.End` -> `CompileError`
- Colisao de context keys (dois modulos -> mesmo snake_case) -> `CompileError`
- Eventos nao-atom em `events/0` -> `CompileError`
- Tecnica: `assert_raise CompileError, ~r/mensagem/, fn -> Code.compile_quoted(...) end`

**Engine funcional:**
- `advance/1` — instance pending -> running com step inicial ativo
- `execute_step/2` — chama module.execute/3 com config de `step_configs`, valida `function_exported?`
- `complete_step/4` — move de active para completed, atualiza context com snake_case key
- `activate_transitions/3` — resolve transit/2 e transit/3, ativa targets, fan-in espera predecessors
- `check_completion/1` — marca completed quando active_steps vazio
- `resume_step/3` — retoma step waiting, ativa transicoes
- `step_configs` — config guardado ao ativar, passado ao execute, limpo ao completar

**Context:**
- `put_step_result/3` — grava resultado com snake_case key
- `module_to_context_key/1` — conversao correta, respeita `step_key/0` override

**Built-in steps:**
- `End.events/0` retorna `[:end]`, `execute/3` retorna `{:ok, :end}`
- `Wait.events/0` retorna `[:timeout]`, `execute/3` retorna `{:async}`
- `WaitForEvent.events/0` retorna `[:received]`, `execute/3` retorna `{:async}`
- `Debug.events/0` retorna `[:completed]`, `execute/3` loga e retorna `{:ok, :completed}`

### Integration Tests (Runtime OTP — com supervision tree)

- `Runner.Local` — start_instance -> advance -> steps executam -> completed
- `Runner.Local` — start_instance -> Wait -> schedule_resume -> timeout -> completed
- `Runner.Local` — start_instance -> WaitForEvent -> resume externo -> completed
- Fan-out com TaskSupervisor — steps paralelos executam e convergem no join
- Crash recovery — GenServer morre, DynamicSupervisor reinicia, estado recuperado do Storage
- Storage.ETS — put/get/delete/query com instancias que tem `step_configs`

### Workflows de Teste

| Workflow | Grafo | Testa |
|----------|-------|-------|
| `LinearWorkflow` | A -> B -> End | Caso simples, context propagation |
| `BranchWorkflow` | A ->(:high)-> B, A ->(:low)-> C -> End | Branch via eventos diferentes |
| `ParallelWorkflow` | A -> [B, C] -> Join -> End | Fan-out/fan-in, predecessors |
| `AsyncWorkflow` | A -> Wait -> B -> End | Pausa e resume por timeout |
| `EventWorkflow` | A -> WaitForEvent -> B -> End | Pausa e resume externo |
| `DynamicWorkflow` | A -> transit/3 com @targets -> B ou C -> End | Roteamento dinamico |
| `ConfigWorkflow` | A -> {B, config} -> End | step_configs flow |
| Invalidos | Varios | CompileError pra cada validacao |

## Development Sequencing

### Build Order

1. **Adicionar `libgraph` como dependencia no `mix.exs`** — sem dependencias. Necessario antes de qualquer compile-time validation.

2. **Step behaviour (`steps/step.ex`)** — sem dependencias internas. Adiciona `events/0` e `step_key/0` callbacks, muda event type para `atom()`. Base pra tudo que vem depois.

3. **Built-in steps (wait, wait_for_event, end_step, debug)** — depende de (2). Adiciona `events/0` a cada um, muda returns pra atom. Rapido e valida que o behaviour funciona.

4. **Data structs (`instance.ex`, `execution_entry.ex`)** — sem dependencias entre si. Instance ganha `step_configs`, types mudam de `atom()` pra `module()`. ExecutionEntry muda event type.

5. **Remover `step.ex` e `step_definition.ex`** — depende de (4). Remove os arquivos e todas as referencias no codigo. A partir daqui o projeto nao compila ate o Engine ser adaptado.

6. **`workflow.ex` — reescrita total** — depende de (2, 5). Remove `%Workflow{}` struct e `definition/0`. Implementa o novo macro: `__using__` com register_attribute + `@on_definition` + `@before_compile`. Edge extraction hibrida (transit/2 via `Module.get_definition`, transit/3 via `__on_definition__` + `@targets`). DAG via `libgraph`. Todas as validacoes: ciclos, orphans, fan-out convergence, events x transit cross-validation, context key collision, leaf nodes = End. Gera `__predecessors__/1` e `__graph__/0`. **Este e o item mais complexo e critico.**

7. **Engine (`engine.ex`)** — depende de (4, 6). Remove `StepDefinition` imports. `ensure_started` chama `workflow.start()`. `execute_step/2` recebe module direto, busca config de `step_configs`, valida `function_exported?`. `activate_transitions/3` chama `resolve_transit/3`. `complete_step/4` grava context com snake_case key via `module_to_context_key/1`. Adiciona limpeza de `step_configs` ao completar step.

8. **Runner e entry module (`runner.ex`, `runner/local.ex`, `hephaestus.ex`)** — depende de (7). Atualiza typespecs (event: `atom()`, step_ref: `module()`). `Runner.Local.execute_step/2` privado chama Engine direto sem protocol. `hephaestus.ex` muda guard de `is_binary(event)` pra `is_atom(event)`.

9. **Unit tests — compile-time validation** — depende de (6). Testa todos os cenarios de CompileError: evento sem transit, transit sem evento, ciclo, orphan, fan-out sem join, transit/3 sem @targets, leaf != End, colisao de keys.

10. **Unit tests — engine funcional** — depende de (7). Testa advance, execute_step, complete_step, activate_transitions, resume_step, step_configs flow, context keys. Usa workflows de teste definidos com a nova API.

11. **Integration tests — runtime OTP** — depende de (8, 9, 10). Testa Runner.Local end-to-end: linear, branch, fan-out, async, event, crash recovery.

### Technical Dependencies

- `libgraph` (hex) — unica dependencia externa nova. Bloqueia step 6
- Elixir 1.15+ / OTP 26+ — ja e baseline. `Module.get_definition/2` disponivel desde Elixir 1.12
- Steps 1-7 podem ser desenvolvidos e testados sem processos OTP
- Steps 9-10 podem ser paralelizados apos step 7

**Ponto de nao-retorno:** apos step 5 (remocao de step.ex e step_definition.ex), o projeto nao compila ate steps 6 e 7 estarem completos. Alternativa segura: fazer steps 5-7 num unico commit.

## Monitoring and Observability

Fora de escopo nesta versao (PRD: "Telemetry: Nao entra nesta versao"). Mesma abordagem da v1: Logger em pontos chave do Engine e Runner. Sem mudancas.

## Technical Considerations

### Key Decisions

| Decisao | Escolha | Trade-off |
|---------|---------|-----------|
| Edge extraction de transit/2 | `@before_compile` + `Module.get_definition/2` | Aliases resolvidos, mas extrai de AST literal (seguro porque transit/2 e sem logica) |
| Edge extraction de transit/3 | `__on_definition__` + `@targets` | Requer `Macro.expand` nos args, mas body pode ter logica livre |
| Terminal step | Todo leaf node DEVE ser `Hephaestus.Steps.End` | Menos flexibilidade (sem terminals customizados), mais seguranca (garantia explicita de terminacao) |

### Known Risks

- **AST de transit/2 nao-literal:** se alguem escrever logica no body de transit/2 (violando o contrato), a extracao falha. Mitigacao: validar no `@before_compile` que o body e extraivel e dar erro claro se nao for
- **Aliases em __on_definition__:** `__on_definition__` recebe args como AST com aliases possivelmente nao expandidos. Mitigacao: `Macro.expand/2` com o env do modulo
- **Merge de context em fan-in:** mitigado por namespace automatico via snake_case keys
- **GenServer por instancia em escala alta:** mitigavel com PartitionSupervisor no futuro (fora de escopo)

## Architecture Decision Records

- [ADR-001: Substituicao direta v1->v2](adrs/adr-001.md) — Breaking change, callback-based com pattern matching
- [ADR-002: Edge extraction hibrida](adrs/adr-002.md) — transit/2 via @before_compile + Module.get_definition, transit/3 via __on_definition__ + @targets
- [ADR-003: Terminal step obrigatorio](adrs/adr-003.md) — Todo caminho deve terminar em Hephaestus.Steps.End
