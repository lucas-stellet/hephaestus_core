# Task 08: Adaptar Runner, Runner.Local, e entry module

## Objetivo

Atualizar typespecs (event: `atom()`, step_ref: `module()`). Adaptar Runner.Local pra chamar Engine com module diretamente. Entry module muda guard de resume.

## Arquivos

- `lib/hephaestus/runtime/runner.ex` — atualizar typespecs
- `lib/hephaestus/runtime/runner/local.ex` — adaptar chamadas ao novo Engine
- `lib/hephaestus.ex` — mudar guard de `is_binary(event)` pra `is_atom(event)`

## Depende de

- Task 07 (Engine adaptado)

## Mudancas

### runner.ex
```elixir
# resume event: String.t() -> atom()
@callback resume(instance_id :: String.t(), event :: atom()) :: :ok | {:error, term()}
# schedule_resume step_ref: atom() -> module()
@callback schedule_resume(instance_id :: String.t(), step_ref :: module(), delay_ms :: pos_integer()) :: ...
```

### runner/local.ex
```elixir
# resume guard: is_binary(event) -> is_atom(event)
def resume(instance_id, event) when is_binary(instance_id) and is_atom(event) do

# execute_step privado: chamar Engine.execute_step(instance, step_module) direto
defp execute_step(instance, step_module) do
  Engine.execute_step(instance, step_module)
end

# handle_info scheduled_resume: "timeout" -> :timeout
def handle_info({:scheduled_resume, step_ref}, %{instance: instance} = state) do
  next_state =
    state
    |> with_instance(Engine.resume_step(instance, step_ref, :timeout))
    |> persist_instance()
  {:noreply, next_state, {:continue, :advance}}
end
```

### hephaestus.ex
```elixir
# resume guard: is_binary(event) -> is_atom(event)
def resume(instance_id, event) when is_binary(instance_id) and is_atom(event) do
```

## Test Skeleton

Nenhum test skeleton novo nesta task. Os integration tests (task 11) validam o Runner.Local end-to-end. As mudancas aqui sao mecanicas (typespecs + guards).

## Acoes de validacao

1. Verificar que `mix compile --warnings-as-errors` passa
2. Verificar que os testes unitarios do engine (task 10) ainda passam
