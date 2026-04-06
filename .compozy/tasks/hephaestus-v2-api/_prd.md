# PRD: Hephaestus v2 API

## Overview

Hephaestus v2 API substitui a definição de workflows baseada em structs (`definition/0` -> `%Workflow{steps: [%Step{}]}`) por callbacks com pattern matching idiomático do Elixir. Workflows sao definidos via `start/0` (step inicial), `transit/2` (roteamento estático via pattern matching) e opcionalmente `transit/3` + `@targets` (roteamento dinâmico com context). Cada step declara seus eventos possiveis via `events/0`, permitindo validação cruzada completa em compile-time. Eventos sao atoms. DAG validado via `libgraph`. Breaking change, versão 0.2.0.

Destinada aos mesmos consumidores da v1 -- desenvolvedores Elixir que precisam de workflow orchestration. A migração e validada migrando o PedidoX (app demo) da v1 pra v2.

## Goals

- **API idiomatica**: Workflows definidos com `start/0` + `transit/2` usando pattern matching puro do Elixir -- sem structs intermediários, sem maps gigantes
- **Validacao cruzada em compile-time**: `events/0` de cada step cruzado com clauses do `transit` -- evento sem transit ou transit sem evento declarado = erro de compilação
- **DAG validation via libgraph**: Ciclos, orphans, fan-out sem join, targets inexistentes -- tudo validado em compile-time
- **Roteamento dinâmico opt-in**: `transit/3` com `@targets` quando lógica baseada em context e necessária -- sem comprometer a extração do DAG
- **Backward compatibility zero**: Substituição direta da v1. Versao 0.2.0
- **Validacao via PedidoX**: Migrar o app demo da v1 pra v2 como criterio de sucesso

## User Stories

**Como desenvolvedor Elixir:**

- Quero definir workflows com `start/0` e `transit/2` usando pattern matching pra que o codigo seja legivel e idiomático
- Quero que meus steps declarem `events/0` e o compilador me avise se algum evento não tem transit correspondente, pra pegar erros antes de rodar
- Quero usar `transit/3` com `@targets` quando preciso de roteamento dinâmico baseado em context, sem perder a validação do DAG
- Quero que fan-out seja uma lista no return do transit e que o compilador me obrigue a convergir os branches antes de terminar
- Quero acessar resultados de steps anteriores via `context.steps.validate_order` (snake_case automático) em vez de indexar por módulo
- Quero que eventos sejam atoms pra ter pattern matching consistente e warnings do compilador em typos

## Core Features

**Workflow Callbacks**
- `start/0` retorna módulo inicial (ou `{module, config}`)
- `transit/2` recebe `(from_module, event_atom)` -- pattern matching puro, sem lógica. Retorna módulo, lista (fan-out), ou `{module, config}`
- `transit/3` recebe `(from_module, event_atom, context)` -- lógica dinamica permitida. Requer `@targets` antes da clause pra declarar destinos possiveis pro DAG. `transit/3` sem `@targets` = erro de compilação

**Step Behaviour**
- `events/0` obrigatório -- lista de atoms que o step pode emitir
- `execute/3` retorna `{:ok, atom()}`, `{:ok, atom(), map()}`, `{:async}`, ou `{:error, reason}`
- Built-ins: Wait, WaitForEvent, End, Debug -- todos com events/0

**Compile-time Validation**
- Validacao cruzada: todo evento em `events/0` tem transit, todo transit referencia evento declarado
- DAG via `libgraph`: ciclos, steps órfãos, targets inexistentes
- Fan-out branches devem convergir num join antes de terminal
- Colisao de context keys (snake_case de módulos) = erro
- `transit/3` sem `@targets` = erro

**Context Keys**
- Auto snake_case do ultimo segmento do módulo: `Steps.ValidateOrder` -> `:validate_order`
- Acesso: `context.steps.validate_order.item_count`
- Callback opcional `step_key/0` no step pra override

**Config Flow**
- `step_configs` map no Instance guarda config quando transit retorna `{module, config}`
- `active_steps` continua MapSet
- Config guardado ao ativar step, passado ao execute, limpo ao completar

**Runtime Validation**
- Engine checa `function_exported?(module, :execute, 3)` pra módulos retornados por transit

## User Experience

**Definindo um workflow estático:**

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

**Definindo um workflow com roteamento dinâmico (`transit/3` + `@targets`):**

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

**Definindo um step com `events/0`:**

```elixir
defmodule Steps.CheckInventory do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:done, :out_of_stock]

  @impl true
  def execute(_instance, _config, _context), do: {:ok, :done, %{in_stock: true}}
end
```

**Definindo um step com branching:**

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

**Erros de compilação:**

```
# Evento sem transit
** (CompileError) Steps.CheckInventory declares event :out_of_stock but no transit handles it

# Transit referencia evento não declarado
** (CompileError) transit handles (Steps.CheckInventory, :timeout) but step does not declare :timeout in events/0

# Fan-out sem join
** (CompileError) Branch Steps.CheckInventory from fan-out at Steps.CheckAmount
   terminates with :end without joining. Fan-out branches must converge
   into a common step before reaching :end.

# transit/3 sem @targets
** (CompileError) transit/3 clause for (Steps.CalculateTotal, :calculated) requires @targets annotation

# Colisao de context keys
** (CompileError) Context key collision: Steps.ValidateOrder and Steps.ValidateOrder
   both resolve to :validate_order. Use step_key/0 in one of them to override.
```

**Execução (mesma API da v1):**

```elixir
# Iniciar instância
{:ok, instance_id} = MyApp.Hephaestus.start_instance(OrderWorkflow, %{items: items})

# Retomar instância pausada
:ok = MyApp.Hephaestus.resume(instance_id, :payment_confirmed)

# Acessar context de steps anteriores (dentro de um step)
context.steps.validate_order.item_count
context.steps.calculate_total.total
```

## High-Level Technical Constraints

- Lib Elixir pura -- sem dependência de Phoenix, Ecto, ou banco de dados
- Compatível com Elixir 1.15+ e OTP 26+
- Adiciona `libgraph` como dependência pra validação de DAG
- Storage e Runner adapters mantêm mesma interface da v1
- Breaking change: versão 0.2.0

## Non-Goals (Out of Scope)

- **Coexistência v1/v2**: Sem suporte a API antiga. Substituição direta
- **Compensação/Saga**: Sem rollback automático. Fase futura
- **Telemetry**: Não entra nesta versão
- **Retry policies**: Não entra nesta versão
- **Runtime workflow definition**: Workflows sao codigo, não dados
- **Novas features de engine**: Foco e trocar a API de definição. Engine, Runner, Storage mantêm o mesmo comportamento

## Phased Rollout Plan

### Phase 1 -- Nova API (esta versão, 0.2.0)
- Callbacks `start/0`, `transit/2`, `transit/3` + `@targets`
- `events/0` obrigatório no Step behaviour
- Validacao cruzada events x transit em compile-time
- DAG validation via `libgraph`
- Fan-out branches devem convergir
- Context keys auto snake_case
- Eventos como atoms
- Remover: `%Step{}`, `%Workflow{}`, `StepDefinition` protocol, `definition/0`
- Migrar PedidoX pra nova API
- **Critério de sucesso**: PedidoX migrado e rodando com a nova API

### Phase 2 -- Resiliência (ja planejado no PRD v1)
- Retry policies, timeouts, circuit breakers
- `hephaestus_ecto` -- storage adapter Ecto/PostgreSQL
- `hephaestus_channels`

### Phase 3 -- Observabilidade (ja planejado no PRD v1)
- Telemetry events

## Success Metrics

- **PedidoX migrado**: app demo rodando com `start/0`, `transit/2`, `events/0` -- mesma funcionalidade que na v1
- **Compile-time validation**: workflow com evento sem transit não compila. Fan-out sem join não compila. `transit/3` sem `@targets` não compila
- **Zero structs intermediários**: nenhum `%Step{}`, `%Workflow{}`, ou `StepDefinition` no codigo
- **Testes passando**: todos os testes do core, runner e entry module atualizados e verdes
- **Eventos como atoms**: nenhum string como evento em toda a codebase

## Risks and Mitigations

- **Breaking change**: Toda definição de workflow reescrita. Mitigação: projeto em 0.x sem usuarios externos. PedidoX como validação de migração
- **Extração de AST no @before_compile**: Pode ser fragil com aliases não resolvidos. Mitigação: usar Module.register_attribute com accumulate em vez de extrair do AST diretamente
- **Mesmo módulo em posicoes diferentes**: Fan-out pro mesmo módulo não funciona. Mitigação: documentar que cada módulo = uma posição. Reuso via defdelegate
- **Context key collisions**: Módulos com mesmo ultimo segmento colidem. Mitigação: @before_compile detecta e erro de compilação. step_key/0 como escape hatch

## Architecture Decision Records

- [ADR-001: Substituição direta v1->v2](adrs/adr-001.md) -- Breaking change, callback-based com pattern matching

## Open Questions

- Nenhum -- todos os 18 problemas de design foram discutidos e resolvidos em docs/v2-api-design.md
