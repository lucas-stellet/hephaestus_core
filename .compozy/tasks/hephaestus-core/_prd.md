# PRD: Hephaestus Core

## Overview

O Hephaestus Core é uma lib Elixir para construção e execução de workflows como DAGs. Workflows são definidos em código via callbacks (`steps/0`, `transitions/0`, `initial_step/0`), validados em compile-time, e executados por um engine funcional puro que pode opcionalmente ser envolvido por processos OTP (GenServer + DynamicSupervisor) para suportar steps assíncronos e execução paralela.

A lib resolve o problema de orquestrar fluxos de trabalho multi-step com branching, paralelismo (fan-out/fan-in), e steps assíncronos (waits, eventos externos) sem forçar dependências de banco de dados, UI, ou integrações específicas. O consumidor define seus próprios steps implementando um behaviour e compõe workflows como módulos Elixir.

Destinada a desenvolvedores Elixir que precisam de workflow orchestration em suas aplicações, publicada no Hex.pm e usada internamente em projetos próprios.

## Goals

- **Workflow funcional em compile-time**: Desenvolvedores definem workflows como módulos Elixir com callbacks, recebendo erros de compilação se o grafo for inválido (ciclos, steps órfãos, transitions apontando pra steps inexistentes)
- **Execução de DAGs com paralelismo**: Suportar fan-out (um step dispara vários em paralelo) e fan-in (vários convergem, próximo step só executa quando todos predecessores completam)
- **Dual-mode**: Core funcional puro usável em IEx sem OTP, e runtime com GenServer/DynamicSupervisor para async e paralelismo real
- **Extensibilidade via behaviours**: Steps e connectors são behaviours — a app implementa os seus, a lib não força nenhuma integração concreta
- **Storage como adapter**: Configurado na inicialização da lib no módulo de entrada (`use Hephaestus, storage: Hephaestus.Storage.ETS`), pattern similar ao Repo do Ecto. ETS como adapter padrão no MVP com caminho claro pra Ecto no futuro
- **Rodar um workflow real**: O MVP está pronto quando for possível plugar a lib numa app Elixir existente e executar um workflow de ponta a ponta com steps sync, async e paralelos

## User Stories

**Como desenvolvedor Elixir:**

- Quero definir um workflow como módulo com callbacks (`steps/0`, `transitions/0`, `initial_step/0`) para que a estrutura do fluxo seja código versionado e revisável
- Quero receber erros de compilação se meu workflow tiver ciclos, steps órfãos ou transitions apontando pra steps inexistentes, para pegar problemas antes de rodar
- Quero implementar steps customizados via behaviour (`execute/3`) para encapsular qualquer lógica de negócio da minha app
- Quero executar workflows com fan-out e fan-in para orquestrar tarefas paralelas que convergem num ponto de junção
- Quero usar steps async (wait, wait_for_event) para workflows que dependem de tempo ou eventos externos
- Quero testar meu workflow no IEx sem supervision tree, usando só o core funcional puro
- Quero configurar a lib num único módulo (`use Hephaestus, storage: ...`) e adicionar na supervision tree da minha app, similar ao Ecto Repo
- Quero usar o step debug para inspecionar o contexto acumulado e histórico de execução durante o desenvolvimento

## Core Features

**Definição de Workflow**
- Módulo com `use Hephaestus.Workflow` e callbacks `steps/0`, `transitions/0`, `initial_step/0`
- Transitions aceitam atom (sequencial) ou lista de atoms (fan-out)
- `@before_compile` valida o grafo: ciclos, steps órfãos, targets inexistentes, joins impossíveis
- Computa `__predecessors__/1` em compile-time para resolução de fan-in

**Step Behaviour**
- Contrato: `execute(instance, step, context)` retornando `{:ok, event}`, `{:ok, event, context_updates}`, `{:async}`, ou `{:error, reason}`
- Steps built-in: wait, wait_for_event, end, debug
- Qualquer step pode branchar retornando eventos diferentes — sem step condition dedicado

**Engine Funcional (Core Puro)**
- Executa steps, resolve transições, faz merge de context — sem side-effects
- Fan-out: ativa múltiplos steps a partir de uma transição
- Fan-in: só ativa step quando todos predecessores completaram (`MapSet.subset?`)
- Context de steps paralelos namespaced sob `context.steps.<step_ref>` — sem conflito
- Funciona em IEx sem nenhum processo OTP

**Runtime OTP**
- GenServer por instância via DynamicSupervisor + Registry
- Task.Supervisor para execução paralela de branches fan-out
- Resume de instâncias pausadas (wait, wait_for_event) via mensagem ao GenServer

**Módulo de Entrada (`use Hephaestus`)**
- Configuração centralizada: storage adapter e futuras extensões
- Starta supervision tree interna (Registry, DynamicSupervisor, TaskSupervisor, Storage)
- API pública: `start_instance/2`, `resume/2`, etc.

**Storage Adapter**
- Adapter configurado no módulo de entrada, pattern similar ao Ecto Repo
- Implementação ETS no MVP
- Caminho para Ecto no futuro via `hephaestus_ecto`

**Connector Behaviour**
- Contrato simples: `execute/3` e `supported_actions/0`
- Sem implementações concretas — a app define os seus

## User Experience

**Onboarding — do zero ao primeiro workflow:**

1. Adicionar `{:hephaestus, "~> 0.1"}` no `mix.exs`
2. Criar o módulo de entrada: `use Hephaestus, storage: Hephaestus.Storage.ETS`
3. Adicionar `MyApp.Hephaestus` na supervision tree da app
4. Criar um step implementando o behaviour
5. Criar um workflow com callbacks definindo steps e transitions
6. `MyApp.Hephaestus.start_instance(MyWorkflow, %{dados: "iniciais"})`

**Desenvolvimento e debug:**
- Erros de compilação claros quando o grafo é inválido, com mensagem indicando o problema (ex: "step :notify referenciado em transitions mas não definido em steps/0")
- Step debug inserível em qualquer ponto do workflow para inspecionar estado
- Core puro testável em IEx: criar instance, chamar `Engine.advance/1`, ver resultado — sem precisar startar a app

**Fluxo de uso em produção:**
- `start_instance/2` para iniciar um workflow
- `resume/2` para retomar instâncias pausadas em wait/wait_for_event
- Observar execução via logs (Logger) dos steps e do engine

## High-Level Technical Constraints

- Lib Elixir pura — sem dependência de Phoenix, Ecto, ou banco de dados
- Compatível com Elixir 1.15+ e OTP 26+
- Storage é adapter plugável — ETS no MVP, Ecto como extensão futura
- Workflows são módulos Elixir — não há construção ou modificação em runtime

## Non-Goals (Out of Scope)

- **UI/Dashboard**: Sem interface visual. Observabilidade futura via telemetry events, não incluído no MVP
- **Banco de dados**: Sem Ecto, sem migrations, sem PostgreSQL. Persistência via ETS no MVP; `hephaestus_ecto` como lib futura
- **Telemetry**: Não entra no MVP. Será adicionado em fase posterior
- **Channels**: Sem channels embutidos. Será a lib separada `hephaestus_channels`
- **Implementações concretas de connectors**: A lib só fornece o behaviour, não traz integrações prontas
- **Templates/Notificações**: Responsabilidade da app ou do `hephaestus_channels`
- **CLI**: Sem ferramenta de linha de comando
- **Auth/Users**: Responsabilidade da app host
- **Runtime workflow definition**: Workflows não serão criados/modificados em runtime via API — são módulos Elixir definidos em compile-time
- **Retry/Compensation (Saga)**: Sem rollback automático ou retry policy no engine. Steps que precisam de retry implementam internamente

## Phased Rollout Plan

### MVP (Phase 1) — Core Engine
- Definição de workflows via callbacks com validação de grafo em compile-time
- Step behaviour com built-ins: wait, wait_for_event, end, debug
- Engine funcional puro (sem processos, testável em IEx)
- Runtime OTP: GenServer + DynamicSupervisor + Registry + Task.Supervisor
- DAGs com fan-out/fan-in
- Storage adapter com implementação ETS
- Módulo de entrada (`use Hephaestus`) com supervision tree interna
- Connector behaviour (contrato simples)
- **Critério de sucesso**: plugar numa app Elixir e executar um workflow real com steps sync, async e paralelos

### Phase 2 — Resiliência e Persistência
- Funcionalidades avançadas: retry policies, timeouts em steps, circuit breakers
- `hephaestus_ecto` — storage adapter com Ecto/PostgreSQL
- `hephaestus_channels` — lib de channels com behaviours ricos e lifecycle de mensagens
- Documentação e publicação no Hex.pm

### Phase 3 — Observabilidade
- Telemetry events (workflow:started, step:completed, etc.)

## Success Metrics

- **Funcional**: executar um workflow completo (steps sync + async + fan-out/fan-in) numa app Elixir real sem erros
- **Validação compile-time**: workflows com grafo inválido não compilam, com mensagens de erro claras
- **Dual-mode**: o mesmo workflow roda via Engine puro em IEx e via Runtime com processos OTP
- **Zero acoplamento**: a lib não depende de Phoenix, Ecto, ou qualquer framework — só Elixir/OTP
- **Extensibilidade**: criar um step customizado requer apenas implementar um behaviour com uma função

## Risks and Mitigations

- **Context em fan-in**: Steps paralelos escrevem context_updates simultaneamente. Mitigação: o engine salva o resultado de cada step sob `context.steps.<step_ref>`, namespaced automaticamente. O step no fan-in acessa dados pelo nome do predecessor — sem conflito possível
- **Adoção**: Ecossistema Elixir já tem libs de workflow (Opus, Sage, Oban Pro). Mitigação: diferencial claro — validação de grafo em compile-time + DAGs com fan-out/fan-in nativos, algo que nenhuma lib open-source oferece hoje
- **Complexidade de DAGs**: Fan-out/fan-in adiciona complexidade conceitual para novos usuários. Mitigação: workflows simples (lineares, com branch) funcionam sem precisar saber de DAGs — a complexidade é opt-in
- **Perda de estado com ETS**: Restart da VM perde instâncias em execução. Mitigação: ETS é explicitamente o adapter do MVP; persistência real vem com `hephaestus_ecto` na Phase 2

## Architecture Decision Records

- [ADR-001: Arquitetura do Hephaestus Core](adrs/adr-001.md) — Functional Core + OTP Runtime com DAG, callbacks em vez de macros DSL, storage como adapter

## Open Questions

- Estratégia de merge de context para steps não-paralelos (sequenciais): manter o merge direto no context root (`Map.merge`) ou também namespace por step ref?
- Formato exato do callback `transitions/0`: map de maps como proposto ou considerar alternativas?
- Como o step `wait` gerencia timers internamente no GenServer (Process.send_after vs :timer)?
- Como expor o grafo do workflow para ferramentas externas de visualização?
