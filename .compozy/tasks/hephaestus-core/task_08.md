---
status: pending
domain: Core
type: Feature Implementation
scope: Full
complexity: low
dependencies: []
---

# Task 08: Connector behaviour

## Overview

Definir o behaviour simples de Connector — contrato para integrações com serviços externos. A lib não traz implementações concretas; a app consumidora implementa seus próprios connectors. O behaviour existe no core para padronizar o contrato e permitir que libs futuras (como hephaestus_connectors) construam em cima.

<critical>
- ALWAYS READ the PRD and TechSpec before starting
- REFERENCE TECHSPEC for implementation details — do not duplicate here
- FOCUS ON "WHAT" — describe what needs to be accomplished, not how
- MINIMIZE CODE — show code only to illustrate current structure or problem areas
- TESTS REQUIRED — every task MUST include tests in deliverables
</critical>

<requirements>
- Behaviour DEVE definir callbacks: `execute/3` e `supported_actions/0`
- `execute/3` DEVE receber action (atom), params (map), config (map) e retornar `{:ok, map()}` ou `{:error, term()}`
- `supported_actions/0` DEVE retornar lista de atoms
- Behaviour DEVE ser verificável — módulo que implementa sem todos callbacks gera warning
</requirements>

## Subtasks
- [ ] 8.1 Definir behaviour `Hephaestus.Connectors.Connector`
- [ ] 8.2 Criar mock connector de teste implementando o behaviour

## Implementation Details

### Relevant Files
- `lib/hephaestus/connectors/connector.ex` — behaviour definition

## Deliverables
- Behaviour Connector definido
- Unit tests com 80%+ coverage **(REQUIRED)**

## Tests

### Test file: `test/hephaestus/connectors/connector_test.exs`

```elixir
defmodule Hephaestus.Connectors.ConnectorTest do
  use ExUnit.Case, async: true

  # Mock connector implementing the behaviour
  defmodule TestConnector do
    @behaviour Hephaestus.Connectors.Connector

    @impl true
    def execute(:get_task, params, _config) do
      {:ok, %{id: params[:task_id], title: "Test Task"}}
    end

    def execute(:create_task, params, _config) do
      {:ok, %{id: "new_123", title: params[:title]}}
    end

    def execute(_action, _params, _config) do
      {:error, :unsupported_action}
    end

    @impl true
    def supported_actions, do: [:get_task, :create_task]
  end

  describe "behaviour contract" do
    test "execute/3 returns ok with result map" do
      # Arrange
      params = %{task_id: "123"}
      config = %{api_key: "secret"}

      # Act
      result = TestConnector.execute(:get_task, params, config)

      # Assert
      assert {:ok, %{id: "123", title: "Test Task"}} = result
    end

    test "execute/3 returns error for unsupported action" do
      # Act
      result = TestConnector.execute(:unknown, %{}, %{})

      # Assert
      assert {:error, :unsupported_action} = result
    end

    test "supported_actions/0 returns list of atoms" do
      # Act
      actions = TestConnector.supported_actions()

      # Assert
      assert :get_task in actions
      assert :create_task in actions
      assert length(actions) == 2
    end
  end
end
```

- Unit tests:
  - [x] execute/3 returns ok with result
  - [x] execute/3 returns error for unsupported action
  - [x] supported_actions/0 returns list of atoms
- Test coverage target: >=80%

## Success Criteria
- All tests passing
- Test coverage >=80%
- Behaviour compilável e verificável pelo compilador Elixir
