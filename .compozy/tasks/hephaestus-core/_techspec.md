# TechSpec: Hephaestus Core MVP

## Executive Summary

Hephaestus Core é uma lib Elixir de workflow engine com arquitetura em camadas: um core funcional puro (structs + funções sem side-effects, testável em IEx) envolvido por um runtime OTP (GenServer + DynamicSupervisor + TaskSupervisor). Workflows são definidos em compile-time via callback único `definition/0` retornando struct `%Workflow{}` com lista de steps. Cada step é uma struct que implementa o protocolo `StepDefinition`, permitindo extensibilidade por libs externas (channels, connectors). Execução suporta DAGs com fan-out/fan-in. Storage e Runner são adapters configuráveis no módulo de entrada (`use Hephaestus`).

Trade-offs: mais código que um engine puramente funcional em troca de dual-mode (core puro + runtime OTP) e extensibilidade via protocolo em troca de indireção adicional.

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
│  │  Engine.advance/1     │◄───│  Workflow (callbacks)  │ │
│  │  Engine.execute_step  │    │  definition/0          │ │
│  │  Engine.complete_step │    │  __predecessors__/1    │ │
│  │  Engine.resume        │    │  __step__/1            │ │
│  │                       │    │  (@before_compile)     │ │
│  │  Instance (struct)    │    └────────────────────────┘ │
│  │  Context (struct)     │                               │
│  │  ExecutionEntry       │                               │
│  └───────────────────────┘                               │
│                                                         │
│  ┌─────────────────────┐    ┌────────────────────────┐  │
│  │  Steps               │    │  Connectors            │  │
│  │  Step (behaviour)    │    │  Connector (behaviour) │  │
│  │  ├─ Wait             │    │  (sem implementações)  │  │
│  │  ├─ WaitForEvent     │    └────────────────────────┘  │
│  │  ├─ End              │                                │
│  │  └─ Debug            │                                │
│  └─────────────────────┘                                 │
│                                                         │
│  ┌─────────────────────┐                                 │
│  │  StepDefinition      │                                │
│  │  (protocol)          │                                │
│  │  ├─ Core.Step (impl) │                                │
│  │  └─ extensível       │                                │
│  └─────────────────────┘                                 │
└─────────────────────────────────────────────────────────┘
```

### Directory Structure

```
lib/hephaestus/
  core/
    engine.ex            # Funções puras: advance, execute_step, complete_step, resume
    instance.ex          # Struct da instância de workflow
    context.ex           # Struct do context (initial + steps)
    workflow.ex          # Struct + behaviour do workflow
    step.ex              # Struct genérica + implementação do protocolo
    execution_entry.ex   # Struct do histórico de execução
    step_definition.ex   # Protocolo StepDefinition
  runtime/
    runner.ex            # Behaviour do runner
    runner/local.ex      # Runner.Local: GenServer + DynamicSup + behaviour
    storage.ex           # Behaviour do storage
    storage/ets.ex       # Storage.ETS: implementação ETS
  steps/
    step.ex              # Behaviour do step (execute/3)
    wait.ex              # Built-in: pausa por duração
    wait_for_event.ex    # Built-in: pausa até evento externo
    end_step.ex          # Built-in: marca instância como completa
    debug.ex             # Built-in: despeja context e histórico
  connectors/
    connector.ex         # Behaviour do connector
  hephaestus.ex          # use Hephaestus — módulo de entrada
```

### Data Flow

1. App chama `MyApp.Hephaestus.start_instance(Workflow, context)`
2. Módulo de entrada delega pro Runner configurado
3. Runner cria `Instance.new(workflow, context)`, persiste no Storage
4. Runner.Local starta GenServer via DynamicSupervisor
5. GenServer chama `Engine.advance(instance)` — core puro
6. Engine itera `active_steps`, executa cada step via protocolo `StepDefinition`
7. Engine resolve transições, computa fan-in via `__predecessors__/1`, atualiza context via `Context.put_step_result/3`
8. GenServer persiste estado atualizado no Storage
9. Em fan-out, GenServer usa TaskSupervisor pra paralelismo real
10. Em wait/wait_for_event, GenServer pausa e espera resume

## Implementation Design

### Core Interfaces

**Protocolo StepDefinition**
```elixir
defprotocol Hephaestus.StepDefinition do
  def ref(step)
  def module(step)
  def config(step)
  def transitions(step)
end
```

**Step genérico (core)**
```elixir
defmodule Hephaestus.Core.Step do
  @enforce_keys [:ref, :module]
  defstruct [:ref, :module, :config, :transitions]

  defimpl Hephaestus.StepDefinition do
    def ref(step), do: step.ref
    def module(step), do: step.module
    def config(step), do: step.config
    def transitions(step), do: step.transitions
  end
end
```

**Workflow — callback único retornando struct**
```elixir
defmodule Hephaestus.Core.Workflow do
  @enforce_keys [:initial_step, :steps]
  defstruct [:initial_step, :steps]

  @callback definition() :: t()
end
```

**Step Behaviour**
```elixir
defmodule Hephaestus.Steps.Step do
  @callback execute(
    instance :: Instance.t(),
    config :: map() | nil,
    context :: Context.t()
  ) ::
    {:ok, event :: String.t()}
    | {:ok, event :: String.t(), context_updates :: map()}
    | {:async}
    | {:error, reason :: term()}
end
```

**Runner Behaviour**
```elixir
defmodule Hephaestus.Runtime.Runner do
  @callback start_instance(
    workflow :: module(),
    context :: map(),
    opts :: keyword()
  ) :: {:ok, instance_id :: String.t()} | {:error, reason :: term()}

  @callback resume(
    instance_id :: String.t(),
    event :: String.t()
  ) :: :ok | {:error, reason :: term()}

  @callback schedule_resume(
    instance_id :: String.t(),
    step_ref :: atom(),
    delay_ms :: pos_integer()
  ) :: {:ok, reference :: term()} | {:error, reason :: term()}
end
```

**Storage Behaviour**
```elixir
defmodule Hephaestus.Runtime.Storage do
  @callback get(instance_id :: String.t()) ::
              {:ok, Instance.t()} | {:error, :not_found}
  @callback put(instance :: Instance.t()) :: :ok
  @callback delete(instance_id :: String.t()) :: :ok
  @callback query(filters :: keyword()) :: [Instance.t()]
end
```

**Connector Behaviour**
```elixir
defmodule Hephaestus.Connectors.Connector do
  @callback execute(action :: atom(), params :: map(), config :: map()) ::
              {:ok, result :: map()} | {:error, reason :: term()}
  @callback supported_actions() :: [atom()]
end
```

**Engine — funções puras**
```elixir
defmodule Hephaestus.Core.Engine do
  @spec advance(Instance.t()) ::
    {:ok, Instance.t()} | {:error, reason :: term()}

  @spec execute_step(Instance.t(), step_def :: any()) ::
    {:ok, String.t()} | {:ok, String.t(), map()} | {:async} | {:error, term()}

  @spec complete_step(Instance.t(), atom(), String.t(), map()) ::
    Instance.t()

  @spec resume(Instance.t(), String.t()) ::
    Instance.t()
end
```

### Data Models

**Instance**
```elixir
defmodule Hephaestus.Core.Instance do
  @enforce_keys [:id, :workflow]
  defstruct [
    :id,
    :workflow,
    :current_step,
    status: :pending,
    context: %Context{},
    active_steps: MapSet.new(),
    completed_steps: MapSet.new(),
    execution_history: []
  ]

  @type status :: :pending | :running | :waiting | :completed | :failed
end
```

**Context**
```elixir
defmodule Hephaestus.Core.Context do
  @enforce_keys [:initial]
  defstruct [
    initial: %{},
    steps: %{}
  ]

  def new(initial_data), do: %__MODULE__{initial: initial_data}

  def put_step_result(context, step_ref, result) do
    %{context | steps: Map.put(context.steps, step_ref, result)}
  end
end
```

**Workflow**
```elixir
defmodule Hephaestus.Core.Workflow do
  @enforce_keys [:initial_step, :steps]
  defstruct [:initial_step, :steps]
end
```

**ExecutionEntry**
```elixir
defmodule Hephaestus.Core.ExecutionEntry do
  @enforce_keys [:step_ref, :event, :timestamp]
  defstruct [:step_ref, :event, :timestamp, :context_updates]
end
```

**Storage (ETS)**
- Tabela `:set` com `instance_id` como key
- Valor: `Instance.t()` serializado
- Query por filtros: scan da tabela com `:ets.match_object` ou `:ets.foldl`

### Workflow Definition Example

```elixir
defmodule MyApp.Workflows.ProcessOrder do
  use Hephaestus.Workflow
  alias Hephaestus.Core.Step

  @impl true
  def definition do
    %Hephaestus.Core.Workflow{
      initial_step: :validate,
      steps: [
        %Step{
          ref: :validate,
          module: MyApp.Steps.ValidateOrder,
          transitions: %{"valid" => :notify, "invalid" => :done}
        },
        %Step{
          ref: :notify,
          module: MyApp.Steps.NotifyCustomer,
          config: %MyApp.Steps.NotifyConfig{recipient_key: :validate},
          transitions: %{"sent" => :done}
        },
        %Step{
          ref: :done,
          module: Hephaestus.Steps.End
        }
      ]
    }
  end
end
```

### Fan-out / Fan-in Example

```elixir
def definition do
  %Workflow{
    initial_step: :start,
    steps: [
      %Step{
        ref: :start,
        module: MyApp.Steps.ReceiveOrder,
        transitions: %{"received" => [:check_stock, :check_fraud]}
      },
      %Step{
        ref: :check_stock,
        module: MyApp.Steps.CheckStock,
        transitions: %{"done" => :approve}
      },
      %Step{
        ref: :check_fraud,
        module: MyApp.Steps.CheckFraud,
        transitions: %{"done" => :approve}
      },
      %Step{
        ref: :approve,
        module: MyApp.Steps.ApproveOrder,
        transitions: %{"approved" => :done}
      },
      %Step{ref: :done, module: Hephaestus.Steps.End}
    ]
  }
end
```

### Runner.Local Implementation

```elixir
defmodule Hephaestus.Runner.Local do
  @behaviour Hephaestus.Runtime.Runner
  use GenServer

  # --- Runner behaviour ---

  @impl Hephaestus.Runtime.Runner
  def start_instance(workflow, context, opts) do
    instance = Instance.new(workflow, context)
    :ok = opts[:storage].put(instance)

    {:ok, _pid} =
      DynamicSupervisor.start_child(
        opts[:dynamic_supervisor],
        {__MODULE__, {instance, opts}}
      )

    {:ok, instance.id}
  end

  @impl Hephaestus.Runtime.Runner
  def resume(instance_id, event) do
    GenServer.cast(via(instance_id), {:resume, event})
  end

  @impl Hephaestus.Runtime.Runner
  def schedule_resume(instance_id, step_ref, delay_ms) do
    GenServer.call(via(instance_id), {:schedule_resume, step_ref, delay_ms})
  end

  # --- GenServer ---

  def start_link({instance, opts}) do
    GenServer.start_link(__MODULE__, {instance, opts},
      name: via(instance.id)
    )
  end

  defp via(instance_id) do
    {:via, Registry, {Hephaestus.Registry, instance_id}}
  end

  @impl GenServer
  def init({instance, opts}) do
    state = %{instance: instance, storage: opts[:storage]}
    {:ok, state, {:continue, :advance}}
  end

  @impl GenServer
  def handle_continue(:advance, state) do
    case Engine.advance(state.instance) do
      {:ok, %{status: :completed} = instance} ->
        state.storage.put(instance)
        {:stop, :normal, %{state | instance: instance}}

      {:ok, %{status: :waiting} = instance} ->
        state.storage.put(instance)
        {:noreply, %{state | instance: instance}}

      {:ok, %{status: :running} = instance} ->
        state.storage.put(instance)
        {:noreply, %{state | instance: instance}, {:continue, :execute_active}}

      {:error, reason} ->
        instance = Instance.fail(state.instance, reason)
        state.storage.put(instance)
        {:stop, {:error, reason}, %{state | instance: instance}}
    end
  end

  @impl GenServer
  def handle_continue(:execute_active, state) do
    tasks =
      state.instance.active_steps
      |> MapSet.to_list()
      |> Enum.map(fn step_ref ->
        Task.Supervisor.async_nolink(Hephaestus.TaskSupervisor, fn ->
          step_def = state.instance.workflow.__step__(step_ref)
          Engine.execute_step(state.instance, step_def)
        end)
      end)

    results = Task.await_many(tasks)

    instance =
      Enum.zip(MapSet.to_list(state.instance.active_steps), results)
      |> Enum.reduce(state.instance, &handle_step_result/2)

    state = %{state | instance: instance}
    state.storage.put(instance)

    cond do
      MapSet.size(instance.active_steps) > 0 and instance.status == :running ->
        {:noreply, state, {:continue, :execute_active}}

      instance.status == :completed ->
        {:stop, :normal, state}

      true ->
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_cast({:resume, event}, state) do
    instance = Engine.resume(state.instance, event)
    {:noreply, %{state | instance: instance}, {:continue, :advance}}
  end

  @impl GenServer
  def handle_info({:scheduled_resume, step_ref}, state) do
    instance = Engine.resume_step(state.instance, step_ref, "timeout")
    {:noreply, %{state | instance: instance}, {:continue, :advance}}
  end
end
```

### Módulo de Entrada

```elixir
# Gerado por `use Hephaestus`
defmodule MyApp.Hephaestus do
  def start_instance(workflow, context, opts \\ []) do
    runner().start_instance(workflow, context, merge_opts(opts))
  end

  def resume(instance_id, event) do
    runner().resume(instance_id, event)
  end

  def child_spec(_opts) do
    children = [
      {Registry, keys: :unique, name: Hephaestus.Registry},
      {DynamicSupervisor, name: __MODULE__.DynamicSupervisor, strategy: :one_for_one},
      {Task.Supervisor, name: Hephaestus.TaskSupervisor},
      Hephaestus.Storage.ETS
    ]

    %{
      id: __MODULE__,
      start: {Supervisor, :start_link, [children, [strategy: :one_for_one]]},
      type: :supervisor
    }
  end

  defp runner, do: Hephaestus.Runner.Local
  defp merge_opts(opts) do
    Keyword.merge([
      storage: Hephaestus.Storage.ETS,
      runner: Hephaestus.Runner.Local,
      dynamic_supervisor: __MODULE__.DynamicSupervisor
    ], opts)
  end
end
```

## Impact Analysis

| Component | Impact Type | Description and Risk | Required Action |
|-----------|-------------|---------------------|-----------------|
| Hephaestus Core | new | Lib inteira é nova — greenfield | Implementar do zero |
| Hephaestus v1 | unaffected | Projeto original em /Users/lucas/dev/projects/hephaestus permanece intacto | Nenhuma — coexistem |

## Testing Approach

### Unit Tests (Core puro)

- `Engine.advance/1` — workflows lineares, com branch, fan-out, fan-in
- `Engine.execute_step/2` — cada built-in step (wait, wait_for_event, end, debug)
- `Engine.complete_step/4` — merge de context via `Context.put_step_result/3`
- `Engine.resume/2` — retomada de instâncias pausadas
- Validação de grafo no `@before_compile` — ciclos, steps órfãos, targets inexistentes, refs duplicados
- Protocolo `StepDefinition` — structs customizadas implementando o protocolo
- Tudo sem processos, sem supervision tree

### Integration Tests (Runtime OTP)

- `Runner.Local` — start_instance → advance → completed (workflow sync completo)
- `Runner.Local` — start_instance → wait → schedule_resume → timeout → completed
- `Runner.Local` — start_instance → wait_for_event → resume externo → completed
- Fan-out com Task.Supervisor — steps paralelos executam e convergem no fan-in
- Storage.ETS — put/get/delete/query com instâncias reais
- Crash recovery — GenServer morre, DynamicSupervisor reinicia, estado recuperado do ETS

### Workflows de Teste

- `LinearWorkflow` — A → B → End (caso simples)
- `BranchWorkflow` — A → true/false → B ou C → End
- `ParallelWorkflow` — A → [B, C, D] → Join → End (fan-out/fan-in)
- `AsyncWorkflow` — A → Wait(1s) → B → End
- `EventWorkflow` — A → WaitForEvent → B → End
- `InvalidWorkflow` — ciclo, step órfão, target inexistente (compile-time errors)

## Development Sequencing

### Build Order

1. **Data structs** — `Context`, `Instance`, `Workflow`, `Step`, `ExecutionEntry`. Sem dependências
2. **Protocolo `StepDefinition`** — definição + implementação para `Step`. Depende de (1)
3. **`use Hephaestus.Workflow`** — macro com `@before_compile` que valida grafo e computa `__predecessors__/1`. Depende de (1, 2)
4. **Engine funcional** — `advance/1`, `execute_step/2`, `complete_step/4`, `resume/2`. Depende de (1, 2, 3)
5. **Built-in steps** — Wait, WaitForEvent, End, Debug implementando o Step behaviour. Depende de (1)
6. **Workflows de teste** — Linear, Branch, Parallel, Async, Event, Invalid. Depende de (3, 4, 5)
7. **Unit tests do core** — testes do Engine e validação de grafo. Depende de (4, 6)
8. **Storage behaviour + Storage.ETS** — behaviour + implementação ETS. Sem dependências do core
9. **Runner behaviour + Runner.Local** — GenServer + DynamicSupervisor + Registry + TaskSupervisor. Depende de (4, 8)
10. **`use Hephaestus`** — módulo de entrada, supervision tree, API pública. Depende de (8, 9)
11. **Connector behaviour** — definição simples. Sem dependências
12. **Integration tests** — workflows completos via Runtime. Depende de (6, 9, 10)

### Technical Dependencies

- Nenhuma dependência externa bloqueante
- Elixir 1.15+ / OTP 26+ como baseline
- Steps 1-7 podem ser desenvolvidos e testados sem nenhum processo OTP
- Steps 8-10 adicionam a camada de runtime

## Monitoring and Observability

No MVP, sem telemetry. Observabilidade via:

**Logger**
- `Engine.advance` — log de cada step executado, evento retornado, transição resolvida
- `Runner.Local` — log de start/resume/complete/fail de instâncias
- `Storage.ETS` — log de put/get/query em nível debug
- Step `Debug` — despeja context completo e execution_history via Logger.debug

**Structured fields padrão**
- `instance_id`, `workflow`, `step_ref`, `event`, `status` em todas as log entries
- Facilita grep e futura migração pra telemetry (os mesmos campos viram measurements/metadata)

**Sem alerting no MVP** — será adicionado junto com telemetry na Phase 3.

## Technical Considerations

### Key Decisions

- **Protocolo StepDefinition** em vez de behaviour ou map: permite extensibilidade por libs externas sem modificar o core. Cada grupo de step (channel, connector, custom) tem struct própria com campos obrigatórios
- **Runner como adapter** em vez de scheduler: encapsula toda a execução (GenServer hoje, Oban amanhã), não só timers
- **Context como struct** com `initial` + `steps` namespaced: elimina conflitos em fan-in, separação clara entre dados da app e resultados de steps
- **Callback único `definition/0`** retornando `%Workflow{}`: step e suas transitions ficam juntos, grafo legível de cima pra baixo
- **Steps como lista** em vez de map: protocolo funciona com qualquer struct, engine converte pra map internamente

### Known Risks

- **Merge de context em fan-in**: mitigado por namespace automático via `Context.put_step_result/3`
- **GenServer por instância em escala alta**: mitigável com PartitionSupervisor no futuro
- **Perda de estado com ETS**: mitigado pela introdução de `hephaestus_ecto` na Phase 2
- **Runner behaviour pode precisar de callbacks adicionais**: manter mínimo e estender quando necessário

## Architecture Decision Records

- [ADR-001: Arquitetura do Hephaestus Core](adrs/adr-001.md) — Functional Core + OTP Runtime com DAG, callbacks em vez de macros DSL
- [ADR-002: Protocolo StepDefinition](adrs/adr-002.md) — Extensibilidade de tipos de step via protocolo Elixir
- [ADR-003: Runner como adapter](adrs/adr-003.md) — Execução de workflows como adapter substituível (Local → Oban)
- [ADR-004: Context como struct com namespace](adrs/adr-004.md) — Context.initial + Context.steps elimina conflitos em fan-in
