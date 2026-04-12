# Business Key Obrigatoria e Facade do Workflow

**Data:** 2026-04-10
**Status:** Aprovado
**Escopo:** hephaestus_core 0.2.0, hephaestus_ecto 0.2.0, hephaestus_oban 0.4.0

## Problema

As instancias de workflow do Hephaestus sao identificadas por UUIDs gerados automaticamente. Consumers que precisam resumir workflows a partir de eventos externos (ex: webhooks, acoes do usuario) precisam carregar o UUID por toda a cadeia de eventos ou fazer queries de lookup pra encontrar a instancia certa. Isso cria acoplamento entre produtores de eventos e o runtime do workflow.

Engines de workflow do mercado (Temporal, AWS Step Functions, Camunda, Oban Pro Workflows) resolvem isso permitindo que o caller forneca um ID com significado de negocio no momento do start, eliminando a necessidade de lookup.

## Solucao

Todo workflow declara uma business key obrigatoria. A key se torna o prefixo de identidade pra todas as instancias daquele workflow. Uma facade no modulo do workflow oferece `start/2`, `resume/2`, `get/1`, `list/1` e `cancel/1` — o caller so passa o valor cru do negocio. Um modulo dedicado `Hephaestus.Uniqueness` cuida da construcao, validacao e verificacao de unicidade do ID.

## Design

### 1. Workflow DSL — opcao `unique`

O macro `use Hephaestus.Workflow` aceita uma keyword list `:unique` obrigatoria, convertida internamente pra uma struct `%Hephaestus.Workflow.Unique{}`.

#### Struct

```elixir
defmodule Hephaestus.Workflow.Unique do
  @enforce_keys [:key]
  defstruct [:key, scope: :workflow]

  @type scope :: :workflow | :version | :global | :none
  @type t :: %__MODULE__{
    key: String.t(),
    scope: scope()
  }

  @valid_scopes [:workflow, :version, :global, :none]
  @key_format ~r/^[a-z0-9]+$/

  @doc """
  Cria uma struct `%Unique{}` validada a partir de uma keyword list.

  Levanta `ArgumentError` com mensagem descritiva se algum campo for invalido.
  Chamado em compile-time pelo macro do Workflow.
  """
  @spec new!(keyword()) :: t()
  def new!(opts) when is_list(opts) do
    unique = struct!(__MODULE__, opts)
    validate_key!(unique.key)
    validate_scope!(unique.scope)
    unique
  end

  defp validate_key!(key) when is_binary(key) do
    unless Regex.match?(@key_format, key) do
      raise ArgumentError,
        "unique key must contain only lowercase letters and numbers [a-z0-9], got: #{inspect(key)}"
    end
  end

  defp validate_key!(key) do
    raise ArgumentError,
      "unique key must be a string, got: #{inspect(key)}"
  end

  defp validate_scope!(scope) when scope in @valid_scopes, do: :ok

  defp validate_scope!(scope) do
    raise ArgumentError,
      "unique scope must be one of #{inspect(@valid_scopes)}, got: #{inspect(scope)}"
  end
end
```

#### Erros de validacao

O construtor `new!/1` eh chamado em compile-time pelo macro do Workflow. Configuracoes invalidas produzem erros claros durante a compilacao:

| Input invalido | Mensagem de erro |
|---|---|
| `key: 123` | "unique key must be a string, got: 123" |
| `key: "Blueprint"` | "unique key must contain only lowercase letters and numbers [a-z0-9], got: \"Blueprint\"" |
| `key: "blueprint-id"` | "unique key must contain only lowercase letters and numbers [a-z0-9], got: \"blueprint-id\"" |
| `key: "blueprint_id"` | "unique key must contain only lowercase letters and numbers [a-z0-9], got: \"blueprint_id\"" |
| `scope: :invalid` | "unique scope must be one of [:workflow, :version, :global, :none], got: :invalid" |
| sem `key` | "the following keys must also be given when building struct Hephaestus.Workflow.Unique: [:key]" |

#### Campos

##### `key` (obrigatorio)

A business key que identifica a instancia. Define o prefixo do ID armazenado.

**Formato:** String, apenas `[a-z0-9]`. Sem hifens, underscores ou maiusculas.

**Exemplo:**

```elixir
unique: [key: "blueprintid"]

# start("abc123", ctx) -> ID armazenado: "blueprintid::abc123"
# start("550e8400-e29b-41d4-a716-446655440000", ctx) -> "blueprintid::550e8400-e29b-41d4-a716-446655440000"
```

**Use case:** "Para cada blueprint, so pode existir um workflow de incorporacao." A key declara qual entidade de negocio o workflow acompanha. O caller nunca monta o ID — so passa o valor.

##### `scope` (default: `:workflow`)

Define o perimetro onde a unicidade eh aplicada. Quando o caller tenta iniciar uma instancia que ja existe (status `:pending`, `:running` ou `:waiting`) dentro do perimetro, recebe `{:error, :already_running}`.

###### `:workflow` — unicidade por `{id, workflow_module}`

O ID eh unico dentro do mesmo modulo de workflow, independente da versao. Workflows diferentes podem ter instancias ativas com o mesmo ID simultaneamente.

**Chave de unicidade:** `{id, workflow_module}`

**Exemplo:**

```elixir
defmodule IncorporationFlow do
  use Hephaestus.Workflow,
    versions: %{1 => V1, 2 => V2}, current: 2,
    unique: [key: "blueprintid", scope: :workflow]
end

defmodule OnboardingFlow do
  use Hephaestus.Workflow,
    version: 1,
    unique: [key: "blueprintid", scope: :workflow]
end
```

```elixir
# Mesmo blueprint, workflows diferentes
IncorporationFlow.start("abc123", ctx)   # -> {:ok, "blueprintid::abc123"}
OnboardingFlow.start("abc123", ctx)      # -> {:ok, "blueprintid::abc123"} (workflow diferente)

# Mesmo blueprint, mesmo workflow
IncorporationFlow.start("abc123", ctx)   # -> {:ok, "blueprintid::abc123"}
IncorporationFlow.start("abc123", ctx)   # -> {:error, :already_running}

# Mesmo blueprint, versoes diferentes do mesmo workflow
IncorporationFlow.start("abc123", ctx)                 # V1 rodando -> :waiting
IncorporationFlow.start("abc123", ctx, version: 2)     # -> {:error, :already_running}
# Versao nao importa — o scope eh o modulo do workflow inteiro
```

**Use case:** Workflows diferentes operam sobre o mesmo recurso de forma independente. O blueprint "abc123" pode estar em processo de incorporacao E em processo de onboarding ao mesmo tempo — sao fluxos independentes. Mas dentro do mesmo workflow, so uma instancia ativa por blueprint.

**Quando usar:** Caso mais comum. Cada workflow eh responsavel por um fluxo de negocio sobre um recurso. Fluxos diferentes coexistem, duplicatas no mesmo fluxo nao.

###### `:version` — unicidade por `{id, workflow_module, version}`

O ID eh unico dentro da mesma versao de um workflow. Versoes diferentes do mesmo workflow podem ter instancias ativas com o mesmo ID simultaneamente.

**Chave de unicidade:** `{id, workflow_module, version}`

**Exemplo:**

```elixir
defmodule IncorporationFlow do
  use Hephaestus.Workflow,
    versions: %{1 => V1, 2 => V2}, current: 2,
    unique: [key: "blueprintid", scope: :version]
end
```

```elixir
# Mesmo blueprint, versoes diferentes
IncorporationFlow.start("abc123", ctx, version: 1)   # -> {:ok, "blueprintid::abc123"}
IncorporationFlow.start("abc123", ctx, version: 2)   # -> {:ok, "blueprintid::abc123"} (versao diferente)

# Mesmo blueprint, mesma versao
IncorporationFlow.start("abc123", ctx, version: 1)   # -> {:ok, "blueprintid::abc123"}
IncorporationFlow.start("abc123", ctx, version: 1)   # -> {:error, :already_running}
```

**Use case:** Migracao gradual entre versoes. Fazendo rollout da V2 do workflow de incorporacao. O blueprint "abc123" tem uma instancia V1 em `:waiting` (esperando acao do seller). Iniciar a V2 do mesmo blueprint sem cancelar a V1 — as duas versoes coexistem durante o periodo de transicao. Quando a V1 completa ou eh cancelada, so a V2 fica.

**Quando usar:** Deploys blue-green, canary releases, ou qualquer cenario onde duas versoes do mesmo workflow precisam rodar em paralelo sobre o mesmo recurso. Cenario raro, mas necessario em sistemas que nao podem interromper workflows em andamento durante deploys.

###### `:global` — unicidade por `{id}`

O ID eh unico no sistema inteiro. Nenhum workflow, de nenhum tipo ou versao, pode ter uma instancia ativa com o mesmo ID.

**Chave de unicidade:** `{id}`

**Exemplo:**

```elixir
defmodule OnboardingFlow do
  use Hephaestus.Workflow,
    version: 1,
    unique: [key: "companyid", scope: :global]
end

defmodule ComplianceFlow do
  use Hephaestus.Workflow,
    version: 1,
    unique: [key: "companyid", scope: :global]
end
```

```elixir
# Mesmo company ID, workflows diferentes
OnboardingFlow.start("abc123", ctx)    # -> {:ok, "companyid::abc123"}
ComplianceFlow.start("abc123", ctx)    # -> {:error, :already_running}
# Mesmo sendo workflows diferentes, o ID eh global

# Apos o onboarding completar
# OnboardingFlow "abc123" -> :completed (libera o ID)
ComplianceFlow.start("abc123", ctx)    # -> {:ok, "companyid::abc123"}
```

**Use case:** O ID representa um recurso que so pode ter um fluxo ativo de qualquer tipo. Exemplo: onboarding de uma company — enquanto o onboarding esta em andamento, nenhum outro workflow (compliance, billing, etc.) pode iniciar pra essa company. Garante sequenciamento de fluxos sobre o mesmo recurso.

**Quando usar:** Processos exclusivos onde o recurso precisa estar "livre" antes de entrar em outro fluxo. Compliance, onboarding, migracao de dados — situacoes onde fluxos concorrentes sobre o mesmo recurso causariam inconsistencia.

###### `:none` — business key sem constraint de unicidade

O ID usa o prefixo da business key, mas nao ha verificacao de unicidade. Multiplas instancias ativas com o mesmo ID sao permitidas.

**Chave de unicidade:** nenhuma

**Exemplo:**

```elixir
defmodule NotificationFlow do
  use Hephaestus.Workflow,
    version: 1,
    unique: [key: "userid", scope: :none]
end
```

```elixir
# Multiplas notificacoes pro mesmo usuario
NotificationFlow.start("abc123", ctx)   # -> {:ok, "userid::abc123::r7x9k2"}
NotificationFlow.start("abc123", ctx)   # -> {:ok, "userid::abc123::m3p8w1"} (outra instancia)
NotificationFlow.start("abc123", ctx)   # -> {:ok, "userid::abc123::q2n5j4"} (mais uma)
# Cada instancia recebe um sufixo aleatorio pra evitar colisao no storage
```

**Use case:** O workflow precisa de business key pra identidade e pra usar as funcoes facade (`list/1`), mas a natureza do fluxo permite multiplas execucoes simultaneas. Exemplo: workflow de notificacao — o mesmo usuario pode ter varias notificacoes em andamento. O prefixo `"userid::"` permite listar todas as instancias de um usuario, mas nao impede novas.

**Quando usar:** Workflows que sao inerentemente nao-exclusivos. O recurso nao precisa ser "reservado" — o workflow acompanha eventos, nao controla acesso.

**Nota:** Com `scope: :none`, apenas `start/2` e `list/1` sao geradas. `resume/2`, `get/1` e `cancel/1` **nao sao geradas** — seriam ambiguas com multiplas instancias compartilhando o mesmo valor. O caller usa `list/1` pra encontrar instancias e opera via `MyApp.Hephaestus.resume/2` ou `MyApp.Hephaestus.cancel/1` com o ID composto completo (incluindo o sufixo aleatorio).

#### Validacoes compile-time

- `unique` eh obrigatorio — todo workflow precisa declarar uma business key
- `key` deve estar presente e seguir `~r/^[a-z0-9]+$/`
- `scope` deve ser `:workflow`, `:version`, `:global` ou `:none`

#### Funcao gerada

- `__unique__/0` — retorna a struct `%Hephaestus.Workflow.Unique{}`

### 2. Hephaestus.Uniqueness — modulo dedicado

Encapsula construcao de ID, validacao e verificacao de unicidade. Mantem o macro do Workflow e o Runner enxutos.

#### Responsabilidades

- `build_id/2` — constroi o ID composto a partir da config Unique e do valor
- `build_id_with_suffix/2` — constroi ID composto com sufixo aleatorio (pra `scope: :none`)
- `validate_value!/1` — valida o valor passado pelo caller
- `check/5` — verifica unicidade consultando o Storage (retorna `:ok` ou `{:error, :already_running}`)
- `extract_value/1` — extrai o valor cru de um ID composto

#### Formato do ID

Formato: `"key::valor"`

- Separador: `::` (reservado, caller nao pode usar)
- Key: `[a-z0-9]+`
- Valor: `[a-z0-9]+` ou UUID (`[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}`)
- Sub-contextos futuros: `"key::valor::subkey::subvalor"`

O caractere `-` so eh permitido dentro de UUIDs validos (formato hex 8-4-4-4-12). Fora de UUIDs, apenas `[a-z0-9]` eh permitido.

#### Implementacao

```elixir
defmodule Hephaestus.Uniqueness do
  alias Hephaestus.Workflow.Unique

  @active_statuses [:pending, :running, :waiting]

  def build_id(%Unique{key: key}, value) do
    validate_value!(value)
    "#{key}::#{value}"
  end

  def build_id_with_suffix(%Unique{key: key}, value) do
    validate_value!(value)
    suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{key}::#{value}::#{suffix}"
  end

  def extract_value(id) do
    case String.split(id, "::") do
      [_key, value] -> value
      [_key, value, _suffix] -> value  # IDs com scope: :none tem sufixo aleatorio
      _ -> raise ArgumentError, "invalid unique id format: #{id}"
    end
  end

  def validate_value!(value) when is_binary(value) do
    unless valid_value?(value) do
      raise ArgumentError,
        "invalid id value: #{inspect(value)}. Must be [a-z0-9]+ or a valid UUID"
    end
  end

  defp valid_value?(value) do
    simple_value?(value) or uuid_value?(value)
  end

  defp simple_value?(value), do: Regex.match?(~r/^[a-z0-9]+$/, value)

  defp uuid_value?(value),
    do: Regex.match?(~r/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/, value)

  # scope: :none — sem check de unicidade, sempre ok
  def check(%Unique{scope: :none}, _id, _workflow, _version, _query_fn), do: :ok

  # scope: :workflow — unico por {id, workflow_module}
  def check(%Unique{scope: :workflow}, id, workflow, _version, query_fn) do
    case query_fn.(id: id, workflow: workflow, status_in: @active_statuses) do
      [] -> :ok
      [_ | _] -> {:error, :already_running}
    end
  end

  # scope: :version — unico por {id, workflow_module, version}
  def check(%Unique{scope: :version}, id, workflow, version, query_fn) do
    case query_fn.(id: id, workflow: workflow, workflow_version: version, status_in: @active_statuses) do
      [] -> :ok
      [_ | _] -> {:error, :already_running}
    end
  end

  # scope: :global — unico por {id}
  def check(%Unique{scope: :global}, id, _workflow, _version, query_fn) do
    case query_fn.(id: id, status_in: @active_statuses) do
      [] -> :ok
      [_ | _] -> {:error, :already_running}
    end
  end
end
```

### 3. Facade do Workflow — funcoes geradas

Quando um workflow define `unique`, o macro gera funcoes facade no modulo umbrella (ou modulo standalone). Sao wrappers finos que constroem o ID via Uniqueness e delegam pro modulo Hephaestus descoberto via registry de Instances.

#### Funcoes geradas

| Funcao | Assinatura | Descricao |
|---|---|---|
| `start/2` | `start(valor, contexto)` | Constroi ID, verifica unicidade, delega pro `Hephaestus.start_instance` |
| `resume/2` | `resume(valor, evento)` | Constroi ID, delega pro `Hephaestus.resume` |
| `get/1` | `get(valor)` | Constroi ID, delega pro `Storage.get` |
| `list/1` | `list(filtros \\ [])` | Delega pro `Storage.query` com filtro de workflow |
| `cancel/1` | `cancel(valor)` | Constroi ID, valida status cancelavel, muda pra `:cancelled` |

Com `scope: :none`, apenas `start/2` e `list/1` sao geradas. `resume/2`, `get/1` e `cancel/1` **nao sao geradas** — seriam ambiguas com multiplas instancias compartilhando o mesmo valor. O caller usa `list/1` pra encontrar instancias e opera via `MyApp.Hephaestus.resume/2` ou `MyApp.Hephaestus.cancel/1` com o ID composto completo (incluindo o sufixo aleatorio).

#### Comportamento do `cancel/1`

Cancela uma instancia de workflow ativa:

1. Constroi o ID composto a partir do valor
2. Busca a instancia no Storage via `get/1`
3. Valida que a instancia esta em status cancelavel (`:pending`, `:running` ou `:waiting`)
4. Atualiza o status da instancia pra `:cancelled` via Storage

**Retornos:**
- `:ok` — instancia cancelada com sucesso
- `{:error, :not_found}` — nenhuma instancia com esse ID
- `{:error, :not_cancellable}` — instancia esta em status `:completed`, `:failed` ou `:cancelled`

#### Fluxo de uma chamada `start`

```
IncorporationFlow.start("abc123", ctx)
  -> Hephaestus.Instances.lookup!()                              # descobre MyApp.Hephaestus
  -> Uniqueness.build_id(unique, "abc123")                        # -> "blueprintid::abc123"
  -> Uniqueness.check(unique, id, workflow, version, query_fn)    # consulta storage por scope
  -> MyApp.Hephaestus.start_instance(workflow, ctx, id: id)       # delega pro runner com ID custom
  -> {:ok, "blueprintid::abc123"}                                 # retorna o ID composto
```

Pra `scope: :none`, `build_id_with_suffix/2` eh usado e `check/5` eh pulado:

```
NotificationFlow.start("abc123", ctx)
  -> Uniqueness.build_id_with_suffix(unique, "abc123")    # -> "userid::abc123::a1b2c3d4"
  -> MyApp.Hephaestus.start_instance(workflow, ctx, id: id)
  -> {:ok, "userid::abc123::a1b2c3d4"}
```

#### Onde vivem

- **Workflows umbrella:** facade vive apenas no modulo umbrella. Modulos de versao (V1, V2) so definem `start/0`, `transit/3`, `events/0`.
- **Workflows standalone:** o modulo eh ao mesmo tempo definicao e facade.

#### Descoberta do modulo Hephaestus

As funcoes facade chamam `Hephaestus.Instances.lookup!/0` internamente. Se `hephaestus:` eh passado nas opcoes do `use`, eh usado diretamente (pro caso raro de multiplas instancias).

### 4. Hephaestus.Instances — auto-discovery via Registry

Permite que workflows encontrem o modulo Hephaestus sem configuracao explicita.

#### Arquitetura

Usa o `Registry` do Elixir (mesmo padrao do Oban). Um processo Tracker no supervision tree do Hephaestus se registra no boot. Quando morre, o Registry limpa automaticamente.

#### Modulo Hephaestus.Instances

```elixir
defmodule Hephaestus.Instances do
  @registry __MODULE__.Registry

  def child_spec(_arg) do
    [keys: :unique, name: @registry]
    |> Registry.child_spec()
    |> Supervisor.child_spec(id: @registry)
  end

  def register(hephaestus_module) do
    Registry.register(@registry, hephaestus_module, :ok)
  end

  def lookup! do
    case Registry.select(@registry, [{{:"$1", :_, :_}, [], [:"$1"]}]) do
      [single] -> single
      [] -> raise "No Hephaestus instance running. Start one in your supervision tree."
      multiple -> raise "Multiple Hephaestus instances: #{inspect(multiple)}. " <>
                        "Pass hephaestus: MyApp.Hephaestus in your workflow's use options."
    end
  end
end
```

#### Processo Tracker

```elixir
defmodule Hephaestus.Instances.Tracker do
  use GenServer

  def start_link(hephaestus_module) do
    GenServer.start_link(__MODULE__, hephaestus_module)
  end

  def init(hephaestus_module) do
    Hephaestus.Instances.register(hephaestus_module)
    {:ok, hephaestus_module}
  end
end
```

#### Application

O pacote `hephaestus_core` ganha um modulo Application pra iniciar o Registry global:

```elixir
defmodule Hephaestus.Application do
  use Application

  def start(_type, _args) do
    children = [Hephaestus.Instances]
    Supervisor.start_link(children, strategy: :one_for_one, name: Hephaestus.Supervisor)
  end
end
```

Cada `MyApp.Hephaestus` adiciona o Tracker como filho:

```elixir
children = [
  {Registry, keys: :unique, name: registry},
  {DynamicSupervisor, ...},
  {Task.Supervisor, ...},
  {@hephaestus_storage_module, ...},
  {Hephaestus.Instances.Tracker, __MODULE__}
]
```

#### Fallback explicito

Quando existem multiplas instancias, o workflow declara qual usar:

```elixir
use Hephaestus.Workflow,
  unique: [key: "blueprintid"],
  hephaestus: MyApp.Hephaestus
```

### 5. Mudancas em Instance e Storage

#### Instance.new — ID explicito

O construtor que gerava UUIDs automaticamente eh removido. Todas as instancias recebem um ID explicito:

```elixir
def new(workflow, version, context, id) when is_binary(id) do
  %__MODULE__{
    id: id,
    workflow: workflow,
    workflow_version: version,
    context: Context.new(context)
  }
end
```

**Removidos:** `new/1`, `new/2`, `new/3` (todos com UUID auto-gerado). O helper privado `generate_uuid/0` tambem eh removido. Apenas `new/4` com ID explicito permanece. Sem deprecation — nenhum usuario externo ainda.

#### Storage behaviour — novos filtros

O callback `query/1` ganha suporte a filtros adicionais:

| Filtro | Tipo | Proposito |
|---|---|---|
| `:id` | `String.t()` | Check de unicidade — match exato por ID |
| `:workflow` | `module()` | Scope `:workflow` — filtrar por modulo do workflow (ja existe) |
| `:workflow_version` | `pos_integer()` | Scope `:version` — filtrar por versao |
| `:status_in` | `[status()]` | Filtrar instancias ativas `[:pending, :running, :waiting]` |

O callback `query/1` ja existe no behaviour Storage (aceita filtros `:status` e `:workflow`). Isso estende com filtros adicionais — nenhum callback novo necessario.

#### Storage.ETS — implementacao dos filtros

```elixir
defp match_filter?({:id, id}, instance), do: instance.id == id
defp match_filter?({:workflow, mod}, instance), do: instance.workflow == mod
defp match_filter?({:workflow_version, v}, instance), do: instance.workflow_version == v
defp match_filter?({:status_in, statuses}, instance), do: instance.status in statuses
```

### 6. Mudancas no macro entry-point do Hephaestus

#### Tracker no supervision tree

```elixir
children = [
  # ... filhos existentes ...
  {Hephaestus.Instances.Tracker, __MODULE__}
]
```

#### start_instance aceita ID custom

```elixir
def start_instance(workflow, context, opts \\ []) do
  id = Keyword.fetch!(opts, :id)

  {version, resolved_module} = resolve_version(workflow, opts)
  telemetry_metadata = Keyword.get(opts, :telemetry_metadata, %{})

  @hephaestus_runner_module.start_instance(
    resolved_module,
    context,
    Keyword.merge(runner_opts(),
      id: id,
      telemetry_metadata: telemetry_metadata,
      workflow_version: version
    )
  )
end
```

#### resume/2 nao muda

Continua recebendo o ID composto completo como string. A facade do workflow constroi o ID e chama `MyApp.Hephaestus.resume("blueprintid::abc123", :finalized)`.

### 7. Impacto nas extensoes

#### hephaestus_ecto (0.1.0 -> 0.2.0)

- **Filtros do Storage:** Suportar `:id`, `:workflow_version`, `:status_in` na query. Mapeia pra clausulas SQL `WHERE`. Sem mudanca de schema — a tabela `workflow_instances` ja tem `id` (string), `workflow`, `workflow_version`, `status`.
- **Runner:** Aceitar `id:` nos opts, passar pro `Instance.new/4`.

#### hephaestus_oban (0.3.0 -> 0.4.0)

- **Filtros do Storage:** Igual ao Ecto — consulta a tabela `workflow_instances`.
- **Runner:** Aceitar `id:` nos opts, propagar pro `Instance.new/4`. Os args dos workers ja carregam `instance_id` como string — nenhuma mudanca necessaria.
- **Advisory lock pro check de unicidade:** A sequencia check-and-create nao eh atomica. Em ambientes multi-node, dois nodes podem verificar simultaneamente, ambos veem "nao existe", e ambos criam. O runner Oban wrappeia o check de unicidade + insert numa transacao com advisory lock:

```sql
SELECT pg_advisory_xact_lock(hashtext('blueprintid::abc123'));
-- check: SELECT ... WHERE id = 'blueprintid::abc123' AND status IN (...)
-- insert: INSERT INTO workflow_instances ...
```

Isso eh responsabilidade do runner, nao do modulo Uniqueness.

#### Coordenacao de releases

| Pacote | Atual | Nova | Depende de |
|---|---|---|---|
| hephaestus_core | 0.1.5 | 0.2.0 | — |
| hephaestus_ecto | 0.1.0 | 0.2.0 | core ~> 0.2.0 |
| hephaestus_oban | 0.3.0 | 0.4.0 | core ~> 0.2.0, ecto ~> 0.2.0 |

Ordem de release: core -> ecto -> oban.

### 8. Breaking changes

| O que muda | Antes | Depois |
|---|---|---|
| `Instance.new` | Gera UUID automaticamente | Recebe ID explicito, UUID removido |
| `unique` no workflow | Nao existia | Obrigatorio |
| `start_instance` | `(workflow, context)` | `(workflow, context, id: "...")` obrigatorio |
| Formato do `Instance.id` | UUID v4 | `"key::valor"` |

Sem avisos de deprecation — nenhum usuario externo ainda.

## Referencias

- **Temporal:** Workflow ID eh fornecido pelo caller como business key. Workflow Id Reuse Policy e Conflict Policy controlam unicidade. Signals usam o business ID diretamente.
- **Camunda 8:** Tags de process instance com padrao `key:value` pra correlacao entre sistemas. Imutaveis apos criacao.
- **AWS Step Functions:** `name` da execucao eh unico por state machine. Start idempotente retorna execucao existente.
- **Oban Pro Workflows:** `workflow_id` aceita string customizada. Default UUIDv7 mas customizavel.
- **Oban Registry:** Usa `Registry` do Elixir pra descoberta de instancias — mesmo padrao adotado pro `Hephaestus.Instances`.
