# Task 06: Reescrever workflow.ex — macro com edge extraction + libgraph

## Objetivo

Reescrita total do `workflow.ex`. Remove `%Workflow{}` struct e `definition/0`. Implementa novo macro com:
- `__using__` registra attributes + @on_definition + @before_compile
- `__on_definition__` captura @targets de transit/3 e acumula em `:hephaestus_dynamic_edges`
- `__before_compile__` extrai edges de transit/2 via `Module.get_definition/2`, merge com dynamic edges, constroi DAG via `libgraph`, roda todas as validacoes, gera `__predecessors__/1` e `__graph__/0`

## Este e o item mais complexo e critico da v2.

## Arquivos

- `lib/hephaestus/core/workflow.ex` — REESCRITA TOTAL

## Depende de

- Task 01 (libgraph)
- Task 02 (Step behaviour com events/0)
- Task 05 (Step struct e StepDefinition removidos)

## Callbacks que o workflow module deve implementar

```elixir
@callback start() :: module() | {module(), config :: map() | struct()}
@callback transit(from :: module(), event :: atom()) :: module() | {module(), config} | [module() | {module(), config}]
# Opcional:
@callback transit(from :: module(), event :: atom(), context :: Context.t()) :: module() | {module(), config} | [module() | {module(), config}]
```

## Validacoes no @before_compile

1. DAG aciclico (via `Graph.is_acyclic?/1`)
2. Todos os steps alcancaveis a partir de `start/0`
3. Fan-out branches convergem antes de End
4. Todo leaf node e `Hephaestus.Steps.End`
5. Cross-validation: todo evento em `events/0` tem transit, todo transit referencia evento declarado
6. Colisao de context keys (snake_case de modulos) = erro
7. transit/3 sem @targets = erro
8. Eventos em events/0 sao atoms

## Funcoes geradas pelo macro

- `__predecessors__/1` — retorna MapSet de modulos que transitam para o dado modulo
- `__graph__/0` — retorna o `Graph.t()` construido em compile-time

## Test Skeleton

**Arquivo:** `test/hephaestus/core/workflow_v2_test.exs`

```elixir
defmodule Hephaestus.Core.WorkflowV2Test do
  use ExUnit.Case, async: true

  describe "valid workflow compilation" do
    test "linear workflow compiles and generates __predecessors__/1" do
      # Arrange & Act
      defmodule LinearFlow do
        use Hephaestus.Workflow

        @impl true
        def start, do: Hephaestus.Test.V2.StepA

        @impl true
        def transit(Hephaestus.Test.V2.StepA, :done), do: Hephaestus.Test.V2.StepB
        def transit(Hephaestus.Test.V2.StepB, :done), do: Hephaestus.Steps.End
      end

      # Assert
      preds_b = LinearFlow.__predecessors__(Hephaestus.Test.V2.StepB)
      assert MapSet.member?(preds_b, Hephaestus.Test.V2.StepA)

      preds_end = LinearFlow.__predecessors__(Hephaestus.Steps.End)
      assert MapSet.member?(preds_end, Hephaestus.Test.V2.StepB)
    end

    test "branch workflow compiles with multiple events from same step" do
      # Arrange & Act
      defmodule BranchFlow do
        use Hephaestus.Workflow

        @impl true
        def start, do: Hephaestus.Test.V2.BranchStep

        @impl true
        def transit(Hephaestus.Test.V2.BranchStep, :approved), do: Hephaestus.Test.V2.ApproveStep
        def transit(Hephaestus.Test.V2.BranchStep, :rejected), do: Hephaestus.Test.V2.RejectStep
        def transit(Hephaestus.Test.V2.ApproveStep, :done), do: Hephaestus.Steps.End
        def transit(Hephaestus.Test.V2.RejectStep, :done), do: Hephaestus.Steps.End
      end

      # Assert
      preds_approve = BranchFlow.__predecessors__(Hephaestus.Test.V2.ApproveStep)
      assert MapSet.member?(preds_approve, Hephaestus.Test.V2.BranchStep)
    end

    test "fan-out workflow compiles when branches converge" do
      # Arrange & Act
      defmodule FanOutFlow do
        use Hephaestus.Workflow

        @impl true
        def start, do: Hephaestus.Test.V2.StepA

        @impl true
        def transit(Hephaestus.Test.V2.StepA, :done), do: [Hephaestus.Test.V2.ParallelA, Hephaestus.Test.V2.ParallelB]
        def transit(Hephaestus.Test.V2.ParallelA, :done), do: Hephaestus.Test.V2.JoinStep
        def transit(Hephaestus.Test.V2.ParallelB, :done), do: Hephaestus.Test.V2.JoinStep
        def transit(Hephaestus.Test.V2.JoinStep, :done), do: Hephaestus.Steps.End
      end

      # Assert
      preds_join = FanOutFlow.__predecessors__(Hephaestus.Test.V2.JoinStep)
      assert MapSet.member?(preds_join, Hephaestus.Test.V2.ParallelA)
      assert MapSet.member?(preds_join, Hephaestus.Test.V2.ParallelB)
    end

    test "workflow with transit/3 and @targets compiles" do
      # Arrange & Act
      defmodule DynamicFlow do
        use Hephaestus.Workflow

        @impl true
        def start, do: Hephaestus.Test.V2.StepA

        @impl true
        @targets [Hephaestus.Test.V2.StepB, Hephaestus.Test.V2.StepC]
        def transit(Hephaestus.Test.V2.StepA, :done, _ctx), do: Hephaestus.Test.V2.StepB

        def transit(Hephaestus.Test.V2.StepB, :done), do: Hephaestus.Steps.End
        def transit(Hephaestus.Test.V2.StepC, :done), do: Hephaestus.Steps.End
      end

      # Assert
      preds_b = DynamicFlow.__predecessors__(Hephaestus.Test.V2.StepB)
      assert MapSet.member?(preds_b, Hephaestus.Test.V2.StepA)

      preds_c = DynamicFlow.__predecessors__(Hephaestus.Test.V2.StepC)
      assert MapSet.member?(preds_c, Hephaestus.Test.V2.StepA)
    end

    test "__graph__/0 returns a Graph struct" do
      # Arrange — reusa LinearFlow do teste acima
      # Act
      graph = LinearFlow.__graph__()

      # Assert
      assert %Graph{} = graph
    end
  end

  describe "compile-time validation errors" do
    test "raises on cycle in DAG" do
      # Assert
      assert_raise CompileError, ~r/[Cc]ycle/, fn ->
        Code.compile_quoted(quote do
          defmodule CycleFlow do
            use Hephaestus.Workflow

            @impl true
            def start, do: Hephaestus.Test.V2.StepA

            @impl true
            def transit(Hephaestus.Test.V2.StepA, :done), do: Hephaestus.Test.V2.StepB
            def transit(Hephaestus.Test.V2.StepB, :done), do: Hephaestus.Test.V2.StepA
          end
        end)
      end
    end

    test "raises on unreachable step" do
      # Assert
      assert_raise CompileError, ~r/[Uu]nreachable/, fn ->
        Code.compile_quoted(quote do
          defmodule OrphanFlow do
            use Hephaestus.Workflow

            @impl true
            def start, do: Hephaestus.Test.V2.StepA

            @impl true
            def transit(Hephaestus.Test.V2.StepA, :done), do: Hephaestus.Steps.End
            # StepB exists in transit but not reachable from start
            def transit(Hephaestus.Test.V2.StepB, :done), do: Hephaestus.Steps.End
          end
        end)
      end
    end

    test "raises on leaf node that is not Hephaestus.Steps.End" do
      # Assert
      assert_raise CompileError, ~r/Hephaestus\.Steps\.End/, fn ->
        Code.compile_quoted(quote do
          defmodule NoEndFlow do
            use Hephaestus.Workflow

            @impl true
            def start, do: Hephaestus.Test.V2.StepA

            @impl true
            def transit(Hephaestus.Test.V2.StepA, :done), do: Hephaestus.Test.V2.StepB
            # StepB is leaf but not End
          end
        end)
      end
    end

    test "raises on fan-out without convergence" do
      # Assert
      assert_raise CompileError, ~r/[Cc]onverg|[Jj]oin/, fn ->
        Code.compile_quoted(quote do
          defmodule NoJoinFlow do
            use Hephaestus.Workflow

            @impl true
            def start, do: Hephaestus.Test.V2.StepA

            @impl true
            def transit(Hephaestus.Test.V2.StepA, :done), do: [Hephaestus.Test.V2.ParallelA, Hephaestus.Test.V2.ParallelB]
            def transit(Hephaestus.Test.V2.ParallelA, :done), do: Hephaestus.Steps.End
            def transit(Hephaestus.Test.V2.ParallelB, :done), do: Hephaestus.Steps.End
          end
        end)
      end
    end

    test "raises on event declared in events/0 without transit" do
      # Assert
      assert_raise CompileError, ~r/declares event.*but no transit/, fn ->
        Code.compile_quoted(quote do
          defmodule MissingTransitFlow do
            use Hephaestus.Workflow

            @impl true
            def start, do: Hephaestus.Test.V2.StepWithExtraEvent

            @impl true
            # StepWithExtraEvent.events/0 returns [:done, :out_of_stock]
            # but only :done has transit
            def transit(Hephaestus.Test.V2.StepWithExtraEvent, :done), do: Hephaestus.Steps.End
          end
        end)
      end
    end

    test "raises on transit referencing event not in events/0" do
      # Assert
      assert_raise CompileError, ~r/does not declare.*in events/, fn ->
        Code.compile_quoted(quote do
          defmodule UndeclaredEventFlow do
            use Hephaestus.Workflow

            @impl true
            def start, do: Hephaestus.Test.V2.StepA

            @impl true
            # StepA.events/0 returns [:done] but transit uses :timeout
            def transit(Hephaestus.Test.V2.StepA, :timeout), do: Hephaestus.Steps.End
          end
        end)
      end
    end

    test "raises on transit/3 without @targets" do
      # Assert
      assert_raise CompileError, ~r/@targets/, fn ->
        Code.compile_quoted(quote do
          defmodule NoTargetsFlow do
            use Hephaestus.Workflow

            @impl true
            def start, do: Hephaestus.Test.V2.StepA

            @impl true
            def transit(Hephaestus.Test.V2.StepA, :done, _ctx), do: Hephaestus.Test.V2.StepB
          end
        end)
      end
    end

    test "raises on context key collision" do
      # Assert
      assert_raise CompileError, ~r/[Cc]ontext key collision|[Cc]ollision/, fn ->
        Code.compile_quoted(quote do
          defmodule CollisionFlow do
            use Hephaestus.Workflow

            @impl true
            # Both modules have last segment "Validate" -> :validate
            def start, do: Hephaestus.Test.V2.Orders.Validate

            @impl true
            def transit(Hephaestus.Test.V2.Orders.Validate, :done), do: Hephaestus.Test.V2.Users.Validate
            def transit(Hephaestus.Test.V2.Users.Validate, :done), do: Hephaestus.Steps.End
          end
        end)
      end
    end

    test "raises on non-atom events in events/0" do
      # Assert
      assert_raise CompileError, ~r/[Aa]tom/, fn ->
        Code.compile_quoted(quote do
          defmodule StringEventFlow do
            use Hephaestus.Workflow

            @impl true
            def start, do: Hephaestus.Test.V2.StringEventStep

            @impl true
            def transit(Hephaestus.Test.V2.StringEventStep, :done), do: Hephaestus.Steps.End
          end
        end)
      end
    end
  end
end
```

## Test Support Necessario

**Arquivo:** `test/support/test_steps_v2.ex`

Criar step modules de teste que implementam o novo behaviour (com `events/0`):

```elixir
defmodule Hephaestus.Test.V2.StepA do
  @behaviour Hephaestus.Steps.Step
  @impl true
  def events, do: [:done]
  @impl true
  def execute(_instance, _config, _context), do: {:ok, :done}
end

defmodule Hephaestus.Test.V2.StepB do
  @behaviour Hephaestus.Steps.Step
  @impl true
  def events, do: [:done]
  @impl true
  def execute(_instance, _config, _context), do: {:ok, :done}
end

defmodule Hephaestus.Test.V2.StepC do
  @behaviour Hephaestus.Steps.Step
  @impl true
  def events, do: [:done]
  @impl true
  def execute(_instance, _config, _context), do: {:ok, :done}
end

defmodule Hephaestus.Test.V2.BranchStep do
  @behaviour Hephaestus.Steps.Step
  @impl true
  def events, do: [:approved, :rejected]
  @impl true
  def execute(_instance, _config, context) do
    if context.initial[:should_approve], do: {:ok, :approved}, else: {:ok, :rejected}
  end
end

defmodule Hephaestus.Test.V2.ApproveStep do
  @behaviour Hephaestus.Steps.Step
  @impl true
  def events, do: [:done]
  @impl true
  def execute(_instance, _config, _context), do: {:ok, :done}
end

defmodule Hephaestus.Test.V2.RejectStep do
  @behaviour Hephaestus.Steps.Step
  @impl true
  def events, do: [:done]
  @impl true
  def execute(_instance, _config, _context), do: {:ok, :done}
end

defmodule Hephaestus.Test.V2.ParallelA do
  @behaviour Hephaestus.Steps.Step
  @impl true
  def events, do: [:done]
  @impl true
  def execute(_instance, _config, _context), do: {:ok, :done, %{parallel: :a}}
end

defmodule Hephaestus.Test.V2.ParallelB do
  @behaviour Hephaestus.Steps.Step
  @impl true
  def events, do: [:done]
  @impl true
  def execute(_instance, _config, _context), do: {:ok, :done, %{parallel: :b}}
end

defmodule Hephaestus.Test.V2.JoinStep do
  @behaviour Hephaestus.Steps.Step
  @impl true
  def events, do: [:done]
  @impl true
  def execute(_instance, _config, _context), do: {:ok, :done}
end

defmodule Hephaestus.Test.V2.StepWithExtraEvent do
  @behaviour Hephaestus.Steps.Step
  @impl true
  def events, do: [:done, :out_of_stock]
  @impl true
  def execute(_instance, _config, _context), do: {:ok, :done}
end

defmodule Hephaestus.Test.V2.AsyncStep do
  @behaviour Hephaestus.Steps.Step
  @impl true
  def events, do: [:timeout]
  @impl true
  def execute(_instance, _config, _context), do: {:async}
end

defmodule Hephaestus.Test.V2.WaitForEventStep do
  @behaviour Hephaestus.Steps.Step
  @impl true
  def events, do: [:received]
  @impl true
  def execute(_instance, _config, _context), do: {:async}
end

# Steps para teste de colisao de context keys
defmodule Hephaestus.Test.V2.Orders.Validate do
  @behaviour Hephaestus.Steps.Step
  @impl true
  def events, do: [:done]
  @impl true
  def execute(_instance, _config, _context), do: {:ok, :done}
end

defmodule Hephaestus.Test.V2.Users.Validate do
  @behaviour Hephaestus.Steps.Step
  @impl true
  def events, do: [:done]
  @impl true
  def execute(_instance, _config, _context), do: {:ok, :done}
end

# Step com eventos string (invalido)
defmodule Hephaestus.Test.V2.StringEventStep do
  @behaviour Hephaestus.Steps.Step
  @impl true
  def events, do: ["done"]  # invalido — deve ser atom
  @impl true
  def execute(_instance, _config, _context), do: {:ok, :done}
end

defmodule Hephaestus.Test.V2.PassWithContextStep do
  @behaviour Hephaestus.Steps.Step
  @impl true
  def events, do: [:done]
  @impl true
  def execute(_instance, _config, _context), do: {:ok, :done, %{processed: true}}
end

defmodule Hephaestus.Test.V2.ConfigStep do
  @behaviour Hephaestus.Steps.Step
  @impl true
  def events, do: [:done]
  @impl true
  def execute(_instance, config, _context), do: {:ok, :done, %{config_received: config}}
end

defmodule Hephaestus.Test.V2.FailStep do
  @behaviour Hephaestus.Steps.Step
  @impl true
  def events, do: [:done]
  @impl true
  def execute(_instance, _config, _context), do: {:error, :something_went_wrong}
end
```

## Sequencia TDD

1. RED: "linear workflow compiles and generates __predecessors__/1" — falha porque macro nao existe
2. GREEN: implementar `__using__` basico com `@before_compile`, extrair edges de transit/2 via `Module.get_definition/2`, gerar `__predecessors__/1`
3. RED: "branch workflow compiles" — pode ja passar se extracao suporta multiplas clauses
4. RED: "fan-out workflow compiles when branches converge" — implementar extracao de listas como targets
5. RED: "workflow with transit/3 and @targets compiles" — implementar `__on_definition__` pra capturar @targets
6. RED: "__graph__/0 returns a Graph struct" — implementar geracao de __graph__/0
7. RED: "raises on cycle in DAG" — implementar `Graph.is_acyclic?/1`
8. RED: "raises on unreachable step" — implementar reachability check
9. RED: "raises on leaf node that is not End" — implementar leaf node validation
10. RED: "raises on fan-out without convergence" — implementar convergence check
11. RED: "raises on event declared in events/0 without transit" — implementar cross-validation
12. RED: "raises on transit referencing event not in events/0" — idem
13. RED: "raises on transit/3 without @targets" — ja implementado no passo 5
14. RED: "raises on context key collision" — implementar `module_to_context_key` + collision check
15. RED: "raises on non-atom events" — implementar atom validation
16. REFACTOR: limpar e organizar o macro
