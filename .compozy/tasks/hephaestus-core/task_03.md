---
status: pending
domain: Core
type: Feature Implementation
scope: Full
complexity: high
dependencies:
  - task_01
---

# Task 03: Workflow macro + Compile-time graph validation

## Overview

Implementar o `use Hephaestus.Workflow` que injeta `@before_compile` para validar o grafo do workflow em tempo de compilação. Deve detectar ciclos, steps órfãos, targets inexistentes, refs duplicados, e computar `__predecessors__/1` e `__step__/1` para uso pelo engine. Erros de compilação claros com mensagens descritivas.

<critical>
- ALWAYS READ the PRD and TechSpec before starting
- REFERENCE TECHSPEC for implementation details — do not duplicate here
- FOCUS ON "WHAT" — describe what needs to be accomplished, not how
- MINIMIZE CODE — show code only to illustrate current structure or problem areas
- TESTS REQUIRED — every task MUST include tests in deliverables
</critical>

<requirements>
- `use Hephaestus.Workflow` DEVE injetar `@behaviour` com callback `definition/0`
- `@before_compile` DEVE validar: ciclos no grafo, steps órfãos, targets inexistentes, refs duplicados
- `@before_compile` DEVE validar que `initial_step` existe na lista de steps
- `@before_compile` DEVE validar que configs são structs quando presentes (não maps soltos)
- DEVE gerar função `__predecessors__/1` computada a partir do grafo reverso
- DEVE gerar função `__step__/1` que retorna o step definition por ref
- DEVE gerar função `__steps_map__/0` convertendo lista de steps pra map por ref
- Erros de compilação DEVEM ter mensagens claras indicando o problema específico
- Fan-out (transição pra lista de atoms) DEVE ser reconhecido na validação
</requirements>

## Subtasks
- [ ] 3.1 Implementar macro `use Hephaestus.Workflow` com `@behaviour` e `@before_compile`
- [ ] 3.2 Implementar validação de refs duplicados
- [ ] 3.3 Implementar validação de initial_step existente
- [ ] 3.4 Implementar validação de targets inexistentes nas transitions
- [ ] 3.5 Implementar detecção de ciclos (DFS-based)
- [ ] 3.6 Implementar detecção de steps órfãos (não alcançáveis do initial_step)
- [ ] 3.7 Computar `__predecessors__/1` a partir do grafo reverso das transitions
- [ ] 3.8 Gerar `__step__/1` e `__steps_map__/0`
- [ ] 3.9 Implementar validação de config struct

## Implementation Details

### Relevant Files
- `lib/hephaestus/core/workflow.ex` — struct + behaviour + macro __using__ + __before_compile__

### Dependent Files
- `lib/hephaestus/core/step.ex` — Step struct validada pelo @before_compile
- `lib/hephaestus/core/step_definition.ex` — Protocolo usado para extrair refs e transitions

### Related ADRs
- [ADR-002: Protocolo StepDefinition](../adrs/adr-002.md) — Protocolo usado para validação de steps

## Deliverables
- Macro `use Hephaestus.Workflow` funcional
- Validação completa do grafo em compile-time
- Funções geradas: `__predecessors__/1`, `__step__/1`, `__steps_map__/0`
- Unit tests com 80%+ coverage **(REQUIRED)**

## Tests

### Test file: `test/hephaestus/core/workflow_validation_test.exs`

```elixir
defmodule Hephaestus.Core.WorkflowValidationTest do
  use ExUnit.Case, async: true

  alias Hephaestus.Core.Step

  describe "valid workflow compilation" do
    test "linear workflow compiles successfully" do
      # Arrange / Act
      defmodule ValidLinear do
        use Hephaestus.Workflow

        @impl true
        def definition do
          %Hephaestus.Core.Workflow{
            initial_step: :start,
            steps: [
              %Step{ref: :start, module: FakeStep, transitions: %{"done" => :finish}},
              %Step{ref: :finish, module: FakeEnd}
            ]
          }
        end
      end

      # Assert
      assert ValidLinear.definition().initial_step == :start
    end

    test "branching workflow compiles successfully" do
      # Arrange / Act
      defmodule ValidBranch do
        use Hephaestus.Workflow

        @impl true
        def definition do
          %Hephaestus.Core.Workflow{
            initial_step: :check,
            steps: [
              %Step{ref: :check, module: FakeStep, transitions: %{"yes" => :approve, "no" => :reject}},
              %Step{ref: :approve, module: FakeStep, transitions: %{"done" => :finish}},
              %Step{ref: :reject, module: FakeStep, transitions: %{"done" => :finish}},
              %Step{ref: :finish, module: FakeEnd}
            ]
          }
        end
      end

      # Assert
      assert ValidBranch.definition().initial_step == :check
    end

    test "fan-out workflow compiles successfully" do
      # Arrange / Act
      defmodule ValidFanOut do
        use Hephaestus.Workflow

        @impl true
        def definition do
          %Hephaestus.Core.Workflow{
            initial_step: :start,
            steps: [
              %Step{ref: :start, module: FakeStep, transitions: %{"go" => [:step_a, :step_b]}},
              %Step{ref: :step_a, module: FakeStep, transitions: %{"done" => :join}},
              %Step{ref: :step_b, module: FakeStep, transitions: %{"done" => :join}},
              %Step{ref: :join, module: FakeStep, transitions: %{"done" => :finish}},
              %Step{ref: :finish, module: FakeEnd}
            ]
          }
        end
      end

      # Assert
      assert ValidFanOut.__predecessors__(:join) |> MapSet.member?(:step_a)
      assert ValidFanOut.__predecessors__(:join) |> MapSet.member?(:step_b)
    end
  end

  describe "invalid workflow detection" do
    test "raises on duplicate step refs" do
      # Assert
      assert_raise CompileError, ~r/duplicate.*ref/i, fn ->
        defmodule DuplicateRefs do
          use Hephaestus.Workflow

          @impl true
          def definition do
            %Hephaestus.Core.Workflow{
              initial_step: :start,
              steps: [
                %Step{ref: :start, module: FakeStep, transitions: %{"done" => :start}},
                %Step{ref: :start, module: FakeStep}
              ]
            }
          end
        end
      end
    end

    test "raises when initial_step does not exist in steps" do
      # Assert
      assert_raise CompileError, ~r/initial_step.*not found/i, fn ->
        defmodule MissingInitial do
          use Hephaestus.Workflow

          @impl true
          def definition do
            %Hephaestus.Core.Workflow{
              initial_step: :nonexistent,
              steps: [
                %Step{ref: :start, module: FakeStep}
              ]
            }
          end
        end
      end
    end

    test "raises when transition targets nonexistent step" do
      # Assert
      assert_raise CompileError, ~r/target.*not found/i, fn ->
        defmodule MissingTarget do
          use Hephaestus.Workflow

          @impl true
          def definition do
            %Hephaestus.Core.Workflow{
              initial_step: :start,
              steps: [
                %Step{ref: :start, module: FakeStep, transitions: %{"done" => :nonexistent}}
              ]
            }
          end
        end
      end
    end

    test "raises when graph contains a cycle" do
      # Assert
      assert_raise CompileError, ~r/cycle/i, fn ->
        defmodule CyclicWorkflow do
          use Hephaestus.Workflow

          @impl true
          def definition do
            %Hephaestus.Core.Workflow{
              initial_step: :a,
              steps: [
                %Step{ref: :a, module: FakeStep, transitions: %{"done" => :b}},
                %Step{ref: :b, module: FakeStep, transitions: %{"done" => :a}}
              ]
            }
          end
        end
      end
    end

    test "raises when step is not reachable from initial_step" do
      # Assert
      assert_raise CompileError, ~r/orphan|unreachable/i, fn ->
        defmodule OrphanStep do
          use Hephaestus.Workflow

          @impl true
          def definition do
            %Hephaestus.Core.Workflow{
              initial_step: :start,
              steps: [
                %Step{ref: :start, module: FakeStep, transitions: %{"done" => :finish}},
                %Step{ref: :orphan, module: FakeStep, transitions: %{"done" => :finish}},
                %Step{ref: :finish, module: FakeEnd}
              ]
            }
          end
        end
      end
    end

    test "raises when config is a plain map instead of struct" do
      # Assert
      assert_raise CompileError, ~r/config.*struct/i, fn ->
        defmodule PlainMapConfig do
          use Hephaestus.Workflow

          @impl true
          def definition do
            %Hephaestus.Core.Workflow{
              initial_step: :start,
              steps: [
                %Step{ref: :start, module: FakeStep, config: %{bad: "config"}, transitions: %{"done" => :finish}},
                %Step{ref: :finish, module: FakeEnd}
              ]
            }
          end
        end
      end
    end
  end

  describe "generated functions" do
    test "__step__/1 returns step definition by ref" do
      # Arrange — uses ValidLinear from above
      defmodule StepLookup do
        use Hephaestus.Workflow

        @impl true
        def definition do
          %Hephaestus.Core.Workflow{
            initial_step: :start,
            steps: [
              %Step{ref: :start, module: FakeStep, transitions: %{"done" => :finish}},
              %Step{ref: :finish, module: FakeEnd}
            ]
          }
        end
      end

      # Act
      step = StepLookup.__step__(:start)

      # Assert
      assert Hephaestus.StepDefinition.ref(step) == :start
      assert Hephaestus.StepDefinition.module(step) == FakeStep
    end

    test "__steps_map__/0 returns all steps indexed by ref" do
      # Act
      steps_map = StepLookup.__steps_map__()

      # Assert
      assert Map.has_key?(steps_map, :start)
      assert Map.has_key?(steps_map, :finish)
      assert map_size(steps_map) == 2
    end

    test "__predecessors__/1 returns empty set for initial step" do
      # Act
      preds = StepLookup.__predecessors__(:start)

      # Assert
      assert MapSet.size(preds) == 0
    end

    test "__predecessors__/1 returns predecessors for fan-in step" do
      # Arrange
      defmodule FanInPreds do
        use Hephaestus.Workflow

        @impl true
        def definition do
          %Hephaestus.Core.Workflow{
            initial_step: :start,
            steps: [
              %Step{ref: :start, module: FakeStep, transitions: %{"go" => [:a, :b]}},
              %Step{ref: :a, module: FakeStep, transitions: %{"done" => :join}},
              %Step{ref: :b, module: FakeStep, transitions: %{"done" => :join}},
              %Step{ref: :join, module: FakeStep, transitions: %{"done" => :finish}},
              %Step{ref: :finish, module: FakeEnd}
            ]
          }
        end
      end

      # Act
      preds = FanInPreds.__predecessors__(:join)

      # Assert
      assert MapSet.equal?(preds, MapSet.new([:a, :b]))
    end
  end
end
```

- Unit tests:
  - [x] Linear workflow compiles
  - [x] Branching workflow compiles
  - [x] Fan-out workflow compiles with predecessors
  - [x] Raises on duplicate refs
  - [x] Raises on missing initial_step
  - [x] Raises on nonexistent transition target
  - [x] Raises on cycle
  - [x] Raises on orphan/unreachable step
  - [x] Raises on plain map config
  - [x] __step__/1 returns step by ref
  - [x] __steps_map__/0 returns indexed map
  - [x] __predecessors__/1 empty for initial
  - [x] __predecessors__/1 correct for fan-in
- Test coverage target: >=80%

## Success Criteria
- All tests passing
- Test coverage >=80%
- Workflows inválidos não compilam com mensagens claras
- __predecessors__/1 computado corretamente para DAGs
