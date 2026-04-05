# Task 002: Step behaviour + Built-in steps

**Wave**: 1 | **Effort**: M
**Depends on**: task-001
**Blocks**: task-004

## Objective

Definir o behaviour `Hephaestus.Steps.Step` com callback `execute/3` e implementar os 4 steps built-in: End, Debug, Wait, WaitForEvent. Cada step é testado isoladamente sem processos OTP.

## Files

**Create:** `lib/hephaestus/steps/step.ex` — behaviour definition
**Create:** `lib/hephaestus/steps/end_step.ex` — step terminal
**Create:** `lib/hephaestus/steps/debug.ex` — step de debug (Logger)
**Create:** `lib/hephaestus/steps/wait.ex` — pausa por duração + delay_ms/1
**Create:** `lib/hephaestus/steps/wait_for_event.ex` — pausa por evento externo
**Create:** `test/hephaestus/steps/end_step_test.exs`
**Create:** `test/hephaestus/steps/debug_test.exs`
**Create:** `test/hephaestus/steps/wait_test.exs`
**Create:** `test/hephaestus/steps/wait_for_event_test.exs`
**Read:** `lib/hephaestus/core/instance.ex` — Instance.t() no callback
**Read:** `lib/hephaestus/core/context.ex` — Context.t() no callback

## Requirements

- Behaviour callback: `execute(instance :: Instance.t(), config :: map() | nil, context :: Context.t())`
- Return types: `{:ok, event}`, `{:ok, event, context_updates}`, `{:async}`, `{:error, reason}`
- End: retorna `{:ok, "completed"}`, ignora config
- Debug: loga context.initial, context.steps, execution_history via Logger.debug, retorna `{:ok, "completed"}`
- Wait: retorna `{:async}`, config aceita `duration` (integer) e `unit` (:second, :minute, :hour, :day). Função `delay_ms/1` converte pra milliseconds
- WaitForEvent: retorna `{:async}`, config aceita `event_name` (string) e `timeout_ms` (optional)
- TDD: ver skeletons em .compozy/tasks/hephaestus-core/task_02.md

## Done when

- [ ] Behaviour definido com callback e @type specs
- [ ] End, Debug, Wait, WaitForEvent implementados
- [ ] Wait.delay_ms/1 converte todas as unidades corretamente
- [ ] Debug loga informações verificáveis via CaptureLog
- [ ] Todos os testes passando
- [ ] Coverage >=80%
