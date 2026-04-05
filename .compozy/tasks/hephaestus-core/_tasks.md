# Hephaestus Core MVP — Tasks

## Task List

| # | Title | Status | Complexity | Dependencies |
|---|-------|--------|------------|-------------|
| 01 | Project scaffolding + Core data structs + StepDefinition protocol | pending | medium | — |
| 02 | Step behaviour + Built-in steps (End, Debug, Wait, WaitForEvent) | pending | medium | task_01 |
| 03 | Workflow macro + Compile-time graph validation | pending | high | task_01 |
| 04 | Engine funcional (advance, execute_step, complete_step, resume) | pending | high | task_01, task_02, task_03 |
| 05 | Storage behaviour + Storage.ETS | pending | medium | task_01 |
| 06 | Runner behaviour + Runner.Local | pending | high | task_04, task_05 |
| 07 | Módulo de entrada (`use Hephaestus`) | pending | medium | task_05, task_06 |
| 08 | Connector behaviour | pending | low | — |

## Dependency Graph

```
task_01 (structs + protocol)
  ├── task_02 (steps built-in)
  ├── task_03 (workflow macro)
  │     └── task_04 (engine) ←── task_02
  ├── task_05 (storage)
  │     └── task_06 (runner) ←── task_04
  │           └── task_07 (módulo de entrada)
  └── task_08 (connector) [independente]
```
