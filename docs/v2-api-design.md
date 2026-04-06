# Hephaestus v2 — Nova API com Callbacks e Pattern Matching

> Decisões de design tomadas em 2026-04-05 durante sessão de brainstorming.

## Motivação

O `definition/0` retornando `%Workflow{}` com lista de `%Step{}` structs gera maps gigantes pouco legíveis. A nova API usa callbacks puros com pattern matching.

## Nova API

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
  def transit(Steps.ConfirmOrder, :confirmed), do: :end
end
```

## Callbacks

### `start/0`

Retorna o step module inicial (ou `{module, config}`).

```elixir
@callback start() :: module() | {module(), config :: map() | struct()}
```

### `transit/2`

Pattern matching puro: recebe quem emitiu + o evento emitido, retorna pra onde ir.

```elixir
@callback transit(from :: module(), event :: atom()) ::
  module()
  | {module(), config :: map() | struct()}
  | [module() | {module(), config :: map() | struct()}]
  | :end
```

**Sem context no transit.** A regra é: steps decidem (retornam eventos), transit roteia (pattern match puro). Isso garante que o transit é 100% extraível em compile-time pro DAG.

Se roteamento dinâmico é necessário, o step emite eventos diferentes baseado na lógica interna.

## Decisões de Design

### 1. Módulo = identidade do step

Steps são identificados pelo seu módulo (atom), não por um ref separado. Sem `%Step{}` struct, sem `StepDefinition` protocol, sem transitions map.

### 2. Mesmo módulo em posições diferentes

**Decisão:** cada módulo aparece no máximo uma vez por workflow. Se o mesmo comportamento é necessário em posições diferentes, o dev cria módulos distintos ou usa `defdelegate`:

```elixir
defmodule Steps.CheckUS, do: defdelegate execute(i, c, ctx), to: Steps.Check
defmodule Steps.CheckEU, do: defdelegate execute(i, c, ctx), to: Steps.Check
```

Na prática, se dois branches fazem coisas diferentes, são módulos diferentes. Se fazem a mesma coisa, provavelmente o workflow pode ser simplificado.

### 3. Branch fica no step, não no transit

Em vez de lógica (`if`) no transit, o step retorna eventos diferentes. O transit é puro mapeamento:

```elixir
# Step decide
defmodule Steps.CalculateTotal do
  def execute(_instance, _config, context) do
    total = Enum.sum(Enum.map(context.initial.items, & &1.price))
    if total > 100 do
      {:ok, :high_value, %{total: total}}
    else
      {:ok, :low_value, %{total: total}}
    end
  end
end

# Transit roteia — sem lógica
def transit(Steps.CalculateTotal, :high_value), do: [Steps.CheckInventory, Steps.CheckFraud]
def transit(Steps.CalculateTotal, :low_value), do: Steps.WaitForPayment
```

### 4. Fan-out é lista no transit

```elixir
def transit(Steps.Start, "ready"), do: [Steps.CheckA, Steps.CheckB, Steps.CheckC]
```

Fan-in é automático: quando múltiplos steps apontam pro mesmo target, o engine espera todos completarem (predecessors via `MapSet.subset?`).

### 5. Config só quando necessário

```elixir
# Sem config — módulo direto
def transit(Steps.Validate, :valid), do: Steps.Process

# Com config — tupla
def transit(Steps.Process, "ready"), do: {Steps.WaitForPayment, %WaitConfig{event_name: "payment"}}
```

### 6. `:end` termina o workflow

```elixir
def transit(Steps.ConfirmOrder, :confirmed), do: :end
```

`Hephaestus.Steps.End` pode ser removido — `:end` substitui.

### 7. Context keys são snake_case do nome do módulo

O engine converte automaticamente:

```elixir
Steps.ValidateOrder  → :validate_order
Steps.CheckFraud     → :check_fraud
```

Acesso legível:

```elixir
context.steps.validate_order.item_count
context.steps.calculate_total.total
```

**Colisão de nomes:** se dois módulos no mesmo workflow geram a mesma key (ex: `MyApp.Orders.Steps.Validate` e `MyApp.Users.Steps.Validate`), o `@before_compile` falha com erro claro.

**Escape hatch:** callback opcional `step_key/0` no step module pra overridar a key derivada.

### 8. Validação runtime de módulos

O engine valida que módulos retornados por `transit/2` implementam `execute/3`:

```elixir
defp validate_step!(module) do
  unless function_exported?(module, :execute, 3) do
    raise "#{inspect(module)} must implement execute/3 (Hephaestus.Steps.Step behaviour)"
  end
end
```

Compile-time valida o grafo (DAG). Runtime valida os módulos (behaviours).

### 9. transit/2 sem context (decidido)

`transit/2` não recebe context. Motivo: se o transit é puro pattern matching sem lógica, context nunca é usado. Toda decisão de roteamento fica no step que emite o evento. Isso torna o transit 100% estático e extraível em compile-time.

## Step Behaviour (sem mudanças)

```elixir
@callback execute(instance :: Instance.t(), config :: map() | nil, context :: Context.t()) ::
  {:ok, event :: atom()}
  | {:ok, event :: atom(), context_updates :: map()}
  | {:async}
  | {:error, reason :: term()}
```

## Retornos do step

```elixir
{:ok, :event}                    # roteia via transit
{:ok, :event, %{dados: "aqui"}}  # roteia + guarda dados em context.steps.<key>
{:async}                          # pausa (wait, wait_for_event)
{:error, reason}                  # falha
```

## O que remove da API atual

- `%Hephaestus.Core.Workflow{}` struct
- `%Hephaestus.Core.Step{}` struct
- `Hephaestus.StepDefinition` protocol
- `definition/0` callback
- `Hephaestus.Steps.End` module (substituído por `:end`)
- transitions map dentro de cada step

### 10. Config flow — `step_configs` no Instance (decidido)

Instance ganha campo `step_configs: %{}` (map de `module => config`). `active_steps` continua `MapSet`.

Ao ativar step com config:
```elixir
instance = %{instance |
  active_steps: MapSet.put(instance.active_steps, Steps.WaitForPayment),
  step_configs: Map.put(instance.step_configs, Steps.WaitForPayment, %WaitConfig{...})
}
```

Ao executar:
```elixir
config = Map.get(instance.step_configs, step_module)  # nil se sem config
step_module.execute(instance, config, instance.context)
```

### 11. Dois modos de transit — estático e dinâmico (decidido)

**`transit/2`** — estático, sem context, body literal. Macro extrai edges automaticamente pra o DAG.

**`transit/3`** — dinâmico, com context, lógica livre. Requer `@targets` antes pra declarar destinos possíveis.

```elixir
# Estático — macro extrai tudo
def transit(Steps.ValidateOrder, :valid), do: Steps.CalculateTotal

# Dinâmico — @targets declara destinos pro DAG
@targets [Steps.CheckInventory, Steps.CheckFraud, Steps.WaitForPayment]
def transit(Steps.CalculateTotal, :calculated, ctx) do
  if ctx.steps.calculate_total.total > 100 do
    [Steps.CheckInventory, Steps.CheckFraud]
  else
    Steps.WaitForPayment
  end
end
```

O `@before_compile` constrói o DAG juntando:
1. Edges de `transit/2` — extraídos dos patterns + body
2. Edges de `transit/3` — extraídos dos patterns + `@targets`

Validação via `libgraph`: ciclos, orphans, reachability, targets existem.

### 12. DAG validation via libgraph (decidido)

Usar `libgraph` (hex package) como dependência pra construção e validação do grafo em compile-time. Puro funcional, sem ETS, maduro (567 stars, 35 dependents).

```elixir
graph = Graph.new()
|> Graph.add_edge(Steps.ValidateOrder, Steps.CalculateTotal)
|> Graph.add_edge(Steps.CalculateTotal, Steps.CheckInventory)

Graph.is_acyclic?(graph)   # validação de ciclos
Graph.topsort(graph)       # ordem topológica
```

### 13. Extração de edges no @before_compile (decidido)

Não extrair do AST das function clauses diretamente. Em vez disso, o macro `use Hephaestus.Workflow` intercepta `def transit` e acumula edges via `Module.register_attribute(:hephaestus_edges, accumulate: true)`:

- `transit/2` → macro analisa patterns (args) + body (return) e acumula edge completo
- `transit/3` → macro analisa patterns (args) + `@targets` acumulado e registra todos os targets possíveis

Isso permite que `transit/3` tenha lógica livre no body sem comprometer a validação do DAG.

### 14. `:end` handling — fan-out branches DEVEM convergir (decidido)

`:end` retornado por `transit` significa "workflow completa". Mas em fan-out, branches paralelos NÃO podem terminar com `:end` individualmente — devem convergir num step comum (join) antes.

**Regra:** branches paralelos DEVEM convergir. `:end` só é válido fora de fan-out.

O `@before_compile` valida via `libgraph`:
1. Detecta fan-outs (transit que retorna lista)
2. Pra cada target de fan-out, percorre o grafo
3. Se branch chega em `:end` sem join → erro de compilação

```
** (CompileError) Branch Steps.CheckInventory from fan-out at Steps.CheckAmount
   terminates with :end without joining. Fan-out branches must converge
   into a common step before reaching :end.
```

Válidos:
```
A → [B, C] → Join → :end          ✅
A → B → :end                       ✅ (linear, sem fan-out)
```

Inválidos:
```
A → [B, C] → B → :end, C → :end   ❌
A → [B, C] → B → Join, C → :end   ❌
```

### 15. Step events/0 obrigatório + validação cruzada em compile-time (decidido)

Cada step DEVE declarar os eventos que pode emitir via callback `events/0`:

```elixir
defmodule Steps.CheckInventory do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:done, :out_of_stock]

  @impl true
  def execute(_instance, _config, _context), do: {:ok, :done, %{in_stock: true}}
end
```

O `@before_compile` cruza `events/0` de cada step com as clauses do `transit`:

- Evento declarado sem transit → erro:
  `Steps.CheckInventory declares event :out_of_stock but no transit handles it`

- Transit referencia evento não declarado → erro:
  `transit handles (Steps.CheckInventory, :timeout) but step does not declare :timeout in events/0`

Step behaviour atualizado:

```elixir
defmodule Hephaestus.Steps.Step do
  @callback events() :: [atom()]
  @callback execute(instance :: Instance.t(), config :: map() | nil, context :: Context.t()) :: result()
end
```

Cobertura total em compile-time: todo evento tem transit, todo transit referencia evento declarado.

### 16. Eventos como atoms, não strings (decidido)

Eventos retornados por steps e usados no transit são atoms, não strings:

```elixir
# Step
def events, do: [:valid, :invalid]
def execute(_instance, _config, _context), do: {:ok, :valid, %{}}

# Transit
def transit(Steps.ValidateOrder, :valid), do: Steps.CalculateTotal
```

Motivos: pattern matching idiomático, sem typos silenciosos, consistente com o resto da API, mais leve no BEAM.

O `@before_compile` valida que eventos declarados em `events/0` são atoms.

### 17. Manter Hephaestus.Steps.End como step concreto (decidido)

Sem `:end` especial no transit. Todo workflow termina num step real que implementa o behaviour:

```elixir
defmodule Hephaestus.Steps.End do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:end]

  @impl true
  def execute(_instance, _config, _context), do: {:ok, :end}
end
```

O transit aponta pro End como qualquer outro step:

```elixir
def transit(Steps.ConfirmOrder, :confirmed), do: Hephaestus.Steps.End
```

Um step é terminal quando seus eventos não têm transit correspondente. `End` é built-in conveniente — o dev pode criar seus próprios terminais.

### 18. Substituição direta da API v1 (decidido)

Breaking change. Remove `definition/0`, `%Step{}`, `StepDefinition` protocol. Versão 0.2.0. Sem coexistência temporária.

## Todos os problemas resolvidos

| # | Problema | Decisão |
|---|----------|---------|
| 1 | Mesmo módulo em posições diferentes | Módulo = identidade. Reuso via `defdelegate` |
| 2 | Config flow | `step_configs: %{}` no Instance. `active_steps` continua MapSet |
| 3 | Extrair patterns do AST | Macro intercepta `def transit` e acumula edges via attribute |
| 4 | `:end` em fan-out | Branches DEVEM convergir. `:end` sem join é erro de compilação |
| 5 | Evento sem match no transit | `events/0` obrigatório (atoms). Validação cruzada em compile-time |
| 6 | Guards e lógica no transit | `transit/2` estático + `transit/3` dinâmico com `@targets` |
| 11 | Eventos como atoms | Atoms em vez de strings. Idiomático, sem typos silenciosos |
| 12 | Manter Steps.End | Step concreto, sem `:end` especial. Terminal = eventos sem transit |
| 13 | Substituição direta | Breaking change v1→v2. Versão 0.2.0 |
| 7 | Context keys legíveis | Auto snake_case do módulo. Colisão = erro de compilação |
| 8 | Validação runtime de módulos | Engine checa `function_exported?(module, :execute, 3)` |
| 9 | DAG validation | `libgraph` como dependência |
| 10 | transit sem context | `transit/2` por padrão. `transit/3` só com `@targets` |
