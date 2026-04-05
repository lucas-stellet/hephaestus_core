---
status: pending
domain: Runtime
type: Feature Implementation
scope: Full
complexity: medium
dependencies:
  - task_01
---

# Task 05: Storage behaviour + Storage.ETS

## Overview

Definir o behaviour de storage e implementar o adapter ETS. O storage é o mecanismo de persistência de instâncias de workflow, configurado no módulo de entrada da app. A implementação ETS é um GenServer que gerencia uma tabela ETS com CRUD e queries por filtros.

<critical>
- ALWAYS READ the PRD and TechSpec before starting
- REFERENCE TECHSPEC for implementation details — do not duplicate here
- FOCUS ON "WHAT" — describe what needs to be accomplished, not how
- MINIMIZE CODE — show code only to illustrate current structure or problem areas
- TESTS REQUIRED — every task MUST include tests in deliverables
</critical>

<requirements>
- Behaviour DEVE definir callbacks: `get/1`, `put/1`, `delete/1`, `query/1`
- `get/1` DEVE retornar `{:ok, Instance.t()}` ou `{:error, :not_found}`
- `put/1` DEVE aceitar `Instance.t()` e retornar `:ok`
- `delete/1` DEVE aceitar instance_id e retornar `:ok`
- `query/1` DEVE aceitar keyword list de filtros e retornar lista de instâncias
- Storage.ETS DEVE ser um GenServer gerenciando tabela `:set`
- Storage.ETS DEVE suportar filtros: `status`, `workflow`
- Storage.ETS DEVE ser nomeado para permitir múltiplas instâncias
</requirements>

## Subtasks
- [ ] 5.1 Definir behaviour `Hephaestus.Runtime.Storage` com callbacks
- [ ] 5.2 Implementar `Hephaestus.Runtime.Storage.ETS` como GenServer
- [ ] 5.3 Implementar CRUD (get, put, delete)
- [ ] 5.4 Implementar query com filtros (status, workflow)

## Implementation Details

### Relevant Files
- `lib/hephaestus/runtime/storage.ex` — behaviour definition
- `lib/hephaestus/runtime/storage/ets.ex` — ETS implementation

### Dependent Files
- `lib/hephaestus/core/instance.ex` — Instance struct armazenada pelo storage

## Deliverables
- Behaviour Storage definido
- Storage.ETS implementado como GenServer
- Unit tests com 80%+ coverage **(REQUIRED)**

## Tests

### Test file: `test/hephaestus/runtime/storage/ets_test.exs`

```elixir
defmodule Hephaestus.Runtime.Storage.ETSTest do
  use ExUnit.Case, async: false

  alias Hephaestus.Runtime.Storage.ETS, as: ETSStorage
  alias Hephaestus.Core.Instance

  setup do
    name = :"test_storage_#{System.unique_integer([:positive])}"
    {:ok, pid} = ETSStorage.start_link(name: name)
    %{storage: name, pid: pid}
  end

  describe "put/1 and get/1" do
    test "stores and retrieves instance", %{storage: storage} do
      # Arrange
      instance = Instance.new(TestWorkflow, %{order_id: 123})

      # Act
      :ok = ETSStorage.put(storage, instance)
      result = ETSStorage.get(storage, instance.id)

      # Assert
      assert {:ok, retrieved} = result
      assert retrieved.id == instance.id
      assert retrieved.context.initial == %{order_id: 123}
    end

    test "returns error for nonexistent instance", %{storage: storage} do
      # Act
      result = ETSStorage.get(storage, "nonexistent")

      # Assert
      assert {:error, :not_found} = result
    end

    test "overwrites existing instance on put", %{storage: storage} do
      # Arrange
      instance = Instance.new(TestWorkflow, %{})
      :ok = ETSStorage.put(storage, instance)

      updated = %{instance | status: :completed}
      :ok = ETSStorage.put(storage, updated)

      # Act
      {:ok, retrieved} = ETSStorage.get(storage, instance.id)

      # Assert
      assert retrieved.status == :completed
    end
  end

  describe "delete/1" do
    test "removes instance from storage", %{storage: storage} do
      # Arrange
      instance = Instance.new(TestWorkflow, %{})
      :ok = ETSStorage.put(storage, instance)

      # Act
      :ok = ETSStorage.delete(storage, instance.id)

      # Assert
      assert {:error, :not_found} = ETSStorage.get(storage, instance.id)
    end

    test "returns ok for nonexistent instance", %{storage: storage} do
      # Act / Assert
      assert :ok = ETSStorage.delete(storage, "nonexistent")
    end
  end

  describe "query/1" do
    test "returns all instances when no filters", %{storage: storage} do
      # Arrange
      instance_a = Instance.new(TestWorkflow, %{})
      instance_b = Instance.new(TestWorkflow, %{})
      :ok = ETSStorage.put(storage, instance_a)
      :ok = ETSStorage.put(storage, instance_b)

      # Act
      results = ETSStorage.query(storage, [])

      # Assert
      assert length(results) == 2
    end

    test "filters by status", %{storage: storage} do
      # Arrange
      pending = Instance.new(TestWorkflow, %{})
      completed = %{Instance.new(TestWorkflow, %{}) | status: :completed}
      :ok = ETSStorage.put(storage, pending)
      :ok = ETSStorage.put(storage, completed)

      # Act
      results = ETSStorage.query(storage, status: :completed)

      # Assert
      assert length(results) == 1
      assert hd(results).status == :completed
    end

    test "filters by workflow", %{storage: storage} do
      # Arrange
      instance_a = Instance.new(WorkflowA, %{})
      instance_b = Instance.new(WorkflowB, %{})
      :ok = ETSStorage.put(storage, instance_a)
      :ok = ETSStorage.put(storage, instance_b)

      # Act
      results = ETSStorage.query(storage, workflow: WorkflowA)

      # Assert
      assert length(results) == 1
      assert hd(results).workflow == WorkflowA
    end

    test "returns empty list when no matches", %{storage: storage} do
      # Arrange
      instance = Instance.new(TestWorkflow, %{})
      :ok = ETSStorage.put(storage, instance)

      # Act
      results = ETSStorage.query(storage, status: :completed)

      # Assert
      assert results == []
    end
  end
end
```

- Unit tests:
  - [x] put + get: stores and retrieves
  - [x] get: returns error for nonexistent
  - [x] put: overwrites existing
  - [x] delete: removes instance
  - [x] delete: ok for nonexistent
  - [x] query: returns all without filters
  - [x] query: filters by status
  - [x] query: filters by workflow
  - [x] query: empty list when no matches
- Test coverage target: >=80%

## Success Criteria
- All tests passing
- Test coverage >=80%
- Storage.ETS funciona como GenServer nomeado
- Query suporta filtros por status e workflow
