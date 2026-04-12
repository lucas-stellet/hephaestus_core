# Hephaestus

A lightweight, compile-time validated workflow engine for Elixir. Define step-based DAG workflows with pattern matching, execute them with built-in support for branching, parallelism, and async operations — all backed by OTP.

## Features

- **Compile-time DAG validation** — catches cycles, unreachable steps, missing terminals, and event mismatches before runtime
- **Pure functional engine** — immutable state transitions, easy to test and reason about
- **Parallel execution** — fan-out to multiple steps, fan-in with automatic predecessor synchronization
- **Async-native** — first-class support for long-running operations, timers, and external event resumption
- **Pluggable adapters** — swap storage (ETS, database, Redis) and runner (local OTP, distributed) implementations
- **Context threading** — immutable initial data plus namespaced step results flowing through the workflow
- **Execution history** — built-in audit trail of every step completion

## Installation

Add `hephaestus` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:hephaestus, "~> 0.1.0"}
  ]
end
```

## Quick Start

### 1. Configure Hephaestus

```elixir
defmodule MyApp.Hephaestus do
  use Hephaestus,
    storage: Hephaestus.Runtime.Storage.ETS,
    runner: Hephaestus.Runtime.Runner.Local
end
```

Add it to your supervision tree:

```elixir
children = [
  MyApp.Hephaestus
]
```

### 2. Define Steps

Each step implements the `Hephaestus.Steps.Step` behaviour:

```elixir
defmodule MyApp.Steps.ValidateOrder do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:valid, :invalid]

  @impl true
  def execute(_instance, _config, context) do
    if context.initial[:item_count] > 0 do
      {:ok, :valid, %{validated_at: DateTime.utc_now()}}
    else
      {:ok, :invalid}
    end
  end
end
```

Steps return one of:
- `{:ok, event}` — synchronous completion
- `{:ok, event, context_updates}` — completion with data
- `{:async}` — pause and wait for external resume
- `{:error, reason}` — failure

### 3. Define a Workflow

Workflows declare a start step, a business key via `unique`, and transitions between steps using pattern matching:

```elixir
defmodule MyApp.Workflows.OrderFlow do
  use Hephaestus.Workflow,
    unique: [key: "orderid"]

  @impl true
  def start, do: MyApp.Steps.ValidateOrder

  @impl true
  def transit(MyApp.Steps.ValidateOrder, :valid, _ctx), do: MyApp.Steps.ProcessPayment
  def transit(MyApp.Steps.ValidateOrder, :invalid, _ctx), do: MyApp.Steps.RejectOrder
  def transit(MyApp.Steps.ProcessPayment, :paid, _ctx), do: Hephaestus.Steps.Done
  def transit(MyApp.Steps.RejectOrder, :rejected, _ctx), do: Hephaestus.Steps.Done
end
```

The `unique: [key: "orderid"]` option is mandatory. It declares the business key used to identify instances (e.g., stored ID becomes `"orderid::abc123"`). The compiler validates the entire DAG at build time — if a path doesn't reach `Hephaestus.Steps.Done`, or if events don't match step declarations, you'll get a compile error.

### 4. Run It

Use the generated facade API on the workflow module — this is the preferred way to interact with workflows:

```elixir
{:ok, "orderid::abc123"} = MyApp.Workflows.OrderFlow.start("abc123", %{item_count: 3, user_id: 42})
```

Or use the lower-level `start_instance` with an explicit `id:` option:

```elixir
{:ok, instance_id} = MyApp.Hephaestus.start_instance(
  MyApp.Workflows.OrderFlow,
  %{item_count: 3, user_id: 42},
  id: "orderid::abc123"
)
```

### 5. Resume Async Workflows

For steps that return `{:async}`, resume them with an external event:

```elixir
:ok = MyApp.Workflows.OrderFlow.resume("abc123", :payment_confirmed)

# Or via the lower-level API:
:ok = MyApp.Hephaestus.resume("orderid::abc123", :payment_confirmed)
```

## Workflow Patterns

### Branching

```elixir
def transit(StepA, :approved, _ctx), do: ApprovalPath
def transit(StepA, :rejected, _ctx), do: RejectionPath
```

### Parallel Execution (Fan-out / Fan-in)

```elixir
# Fan-out: multiple steps run concurrently
def transit(Start, :done, _ctx), do: [BranchA, BranchB, BranchC]

# Fan-in: all branches must complete before Join activates
def transit(BranchA, :done, _ctx), do: Join
def transit(BranchB, :done, _ctx), do: Join
def transit(BranchC, :done, _ctx), do: Join
```

### Dynamic Routing

Use `@targets` to declare possible destinations for context-dependent transitions:

```elixir
@targets [FastTrack, StandardProcess]
def transit(Triage, :routed, ctx) do
  if ctx.initial[:priority] == :high, do: FastTrack, else: StandardProcess
end
```

### Timers and External Events

```elixir
# Wait for a duration
def transit(StepA, :done, _ctx), do: {Hephaestus.Steps.Wait, %{duration: 30, unit: :second}}
def transit(Hephaestus.Steps.Wait, :timeout, _ctx), do: StepB

# Wait for an external event
def transit(StepA, :done, _ctx), do: Hephaestus.Steps.WaitForEvent
def transit(Hephaestus.Steps.WaitForEvent, :received, _ctx), do: StepB
```

## Business Keys and Uniqueness

Every workflow must declare a business key via `unique: [key: "..."]`. The key becomes the ID prefix for all instances: `"orderid::abc123"`.

The `scope` option controls where uniqueness is enforced (default: `:workflow`):

| Scope | Uniqueness per | Use case |
|-------|---------------|----------|
| `:workflow` | `{id, workflow_module}` | One active instance per workflow (most common) |
| `:version` | `{id, workflow_module, version}` | Blue-green deploys with parallel versions |
| `:global` | `{id}` | Exclusive resource lock across all workflows |
| `:none` | No constraint | Multiple concurrent instances (e.g., notifications) |

```elixir
use Hephaestus.Workflow,
  unique: [key: "blueprintid", scope: :workflow]
```

### Facade API

Each workflow module gets generated facade functions for convenient interaction:

```elixir
MyWorkflow.start("abc123", %{amount: 100})   # -> {:ok, "orderid::abc123"}
MyWorkflow.resume("abc123", :payment_done)    # -> :ok
MyWorkflow.get("abc123")                      # -> {:ok, %Instance{}}
MyWorkflow.list(status: :running)             # -> [%Instance{}, ...]
MyWorkflow.cancel("abc123")                   # -> :ok
```

The facade builds the composite ID internally — callers only pass the raw business value.

## Architecture

```
┌─────────────────────────────────────────────┐
│                  Core (pure)                │
│  Workflow ─ Engine ─ Instance ─ Context     │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────┴──────────────────────────┐
│               Runtime (OTP)                 │
│  Runner (Local/Custom) ─ Storage (ETS/Custom)│
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────┴──────────────────────────┐
│                  Steps                      │
│  Done ─ Wait ─ WaitForEvent ─ Debug ─ Custom│
└─────────────────────────────────────────────┘
```

- **Core** — pure functional layer: workflow definition, DAG validation, engine state machine, instance/context structs
- **Runtime** — OTP layer: GenServer-based runner, pluggable storage, supervision tree, crash recovery
- **Steps** — behaviour-based units of work: built-in primitives plus your custom steps

## Documentation

Generate docs with:

```bash
mix docs
```

Generate ASCII execution graphs in your workflow moduledocs:

```bash
mix hephaestus.gen.docs
```

## License

Copyright (c) 2025. All rights reserved.

---

<details>
<summary>Versao em Portugues</summary>

# Hephaestus

Um motor de workflows leve e validado em tempo de compilacao para Elixir. Defina workflows baseados em steps como DAGs usando pattern matching, execute-os com suporte nativo a ramificacao, paralelismo e operacoes assincronas — tudo sobre OTP.

## Funcionalidades

- **Validacao de DAG em tempo de compilacao** — detecta ciclos, steps inalcancaveis, terminais ausentes e eventos incompativeis antes da execucao
- **Engine puramente funcional** — transicoes de estado imutaveis, facil de testar e entender
- **Execucao paralela** — fan-out para multiplos steps, fan-in com sincronizacao automatica de predecessores
- **Nativo para async** — suporte de primeira classe para operacoes longas, timers e retomada por eventos externos
- **Adaptadores plugaveis** — troque implementacoes de storage (ETS, banco de dados, Redis) e runner (OTP local, distribuido)
- **Propagacao de contexto** — dados iniciais imutaveis mais resultados de steps com namespace fluindo pelo workflow
- **Historico de execucao** — trilha de auditoria integrada de cada conclusao de step

## Instalacao

Adicione `hephaestus` a sua lista de dependencias no `mix.exs`:

```elixir
def deps do
  [
    {:hephaestus, "~> 0.1.0"}
  ]
end
```

## Inicio Rapido

### 1. Configure o Hephaestus

```elixir
defmodule MyApp.Hephaestus do
  use Hephaestus,
    storage: Hephaestus.Runtime.Storage.ETS,
    runner: Hephaestus.Runtime.Runner.Local
end
```

Adicione a sua arvore de supervisao:

```elixir
children = [
  MyApp.Hephaestus
]
```

### 2. Defina Steps

Cada step implementa o behaviour `Hephaestus.Steps.Step`:

```elixir
defmodule MyApp.Steps.ValidateOrder do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:valid, :invalid]

  @impl true
  def execute(_instance, _config, context) do
    if context.initial[:item_count] > 0 do
      {:ok, :valid, %{validated_at: DateTime.utc_now()}}
    else
      {:ok, :invalid}
    end
  end
end
```

Steps retornam um dos seguintes:
- `{:ok, event}` — conclusao sincrona
- `{:ok, event, context_updates}` — conclusao com dados
- `{:async}` — pausa e aguarda retomada externa
- `{:error, reason}` — falha

### 3. Defina um Workflow

Workflows declaram um step inicial, uma business key via `unique`, e transicoes via pattern matching:

```elixir
defmodule MyApp.Workflows.OrderFlow do
  use Hephaestus.Workflow,
    unique: [key: "orderid"]

  @impl true
  def start, do: MyApp.Steps.ValidateOrder

  @impl true
  def transit(MyApp.Steps.ValidateOrder, :valid, _ctx), do: MyApp.Steps.ProcessPayment
  def transit(MyApp.Steps.ValidateOrder, :invalid, _ctx), do: MyApp.Steps.RejectOrder
  def transit(MyApp.Steps.ProcessPayment, :paid, _ctx), do: Hephaestus.Steps.Done
  def transit(MyApp.Steps.RejectOrder, :rejected, _ctx), do: Hephaestus.Steps.Done
end
```

A opcao `unique: [key: "orderid"]` e obrigatoria. Ela declara a business key usada para identificar instancias (ex: o ID armazenado sera `"orderid::abc123"`). O compilador valida o DAG inteiro em build time — se um caminho nao chega ao `Hephaestus.Steps.Done`, ou se os eventos nao correspondem as declaracoes dos steps, voce recebe um erro de compilacao.

### 4. Execute

Use a facade API gerada no modulo do workflow — esta e a forma preferida de interagir com workflows:

```elixir
{:ok, "orderid::abc123"} = MyApp.Workflows.OrderFlow.start("abc123", %{item_count: 3, user_id: 42})
```

Ou use a API de baixo nivel com a opcao `id:` explicita:

```elixir
{:ok, instance_id} = MyApp.Hephaestus.start_instance(
  MyApp.Workflows.OrderFlow,
  %{item_count: 3, user_id: 42},
  id: "orderid::abc123"
)
```

### 5. Retome Workflows Assincronos

Para steps que retornam `{:async}`, retome-os com um evento externo:

```elixir
:ok = MyApp.Workflows.OrderFlow.resume("abc123", :payment_confirmed)

# Ou via API de baixo nivel:
:ok = MyApp.Hephaestus.resume("orderid::abc123", :payment_confirmed)
```

## Padroes de Workflow

### Ramificacao

```elixir
def transit(StepA, :approved, _ctx), do: ApprovalPath
def transit(StepA, :rejected, _ctx), do: RejectionPath
```

### Execucao Paralela (Fan-out / Fan-in)

```elixir
# Fan-out: multiplos steps executam concorrentemente
def transit(Start, :done, _ctx), do: [BranchA, BranchB, BranchC]

# Fan-in: todos os branches devem completar antes do Join ativar
def transit(BranchA, :done, _ctx), do: Join
def transit(BranchB, :done, _ctx), do: Join
def transit(BranchC, :done, _ctx), do: Join
```

### Roteamento Dinamico

Use `@targets` para declarar destinos possiveis em transicoes dependentes de contexto:

```elixir
@targets [FastTrack, StandardProcess]
def transit(Triage, :routed, ctx) do
  if ctx.initial[:priority] == :high, do: FastTrack, else: StandardProcess
end
```

### Timers e Eventos Externos

```elixir
# Aguardar por uma duracao
def transit(StepA, :done, _ctx), do: {Hephaestus.Steps.Wait, %{duration: 30, unit: :second}}
def transit(Hephaestus.Steps.Wait, :timeout, _ctx), do: StepB

# Aguardar por um evento externo
def transit(StepA, :done, _ctx), do: Hephaestus.Steps.WaitForEvent
def transit(Hephaestus.Steps.WaitForEvent, :received, _ctx), do: StepB
```

## Business Keys e Unicidade

Todo workflow deve declarar uma business key via `unique: [key: "..."]`. A key se torna o prefixo do ID de todas as instancias: `"orderid::abc123"`.

A opcao `scope` controla onde a unicidade e aplicada (padrao: `:workflow`):

| Scope | Unicidade por | Caso de uso |
|-------|--------------|-------------|
| `:workflow` | `{id, workflow_module}` | Uma instancia ativa por workflow (mais comum) |
| `:version` | `{id, workflow_module, version}` | Deploys blue-green com versoes paralelas |
| `:global` | `{id}` | Lock exclusivo de recurso entre todos os workflows |
| `:none` | Sem restricao | Multiplas instancias simultaneas (ex: notificacoes) |

### Facade API

Cada modulo de workflow ganha funcoes facade geradas automaticamente:

```elixir
MyWorkflow.start("abc123", %{amount: 100})   # -> {:ok, "orderid::abc123"}
MyWorkflow.resume("abc123", :payment_done)    # -> :ok
MyWorkflow.get("abc123")                      # -> {:ok, %Instance{}}
MyWorkflow.list(status: :running)             # -> [%Instance{}, ...]
MyWorkflow.cancel("abc123")                   # -> :ok
```

A facade constroi o ID composto internamente — o caller passa apenas o valor de negocio.

## Arquitetura

```
┌─────────────────────────────────────────────┐
│              Core (puro)                    │
│  Workflow ─ Engine ─ Instance ─ Context     │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────┴──────────────────────────┐
│             Runtime (OTP)                   │
│  Runner (Local/Custom) ─ Storage (ETS/Custom)│
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────┴──────────────────────────┐
│                Steps                        │
│  Done ─ Wait ─ WaitForEvent ─ Debug ─ Custom│
└─────────────────────────────────────────────┘
```

- **Core** — camada puramente funcional: definicao de workflow, validacao de DAG, maquina de estados do engine, structs de instance/context
- **Runtime** — camada OTP: runner baseado em GenServer, storage plugavel, arvore de supervisao, recuperacao de crash
- **Steps** — unidades de trabalho baseadas em behaviour: primitivos built-in mais seus steps customizados

## Documentacao

Gere a documentacao com:

```bash
mix docs
```

Gere grafos ASCII de execucao nos moduledocs dos seus workflows:

```bash
mix hephaestus.gen.docs
```

</details>
