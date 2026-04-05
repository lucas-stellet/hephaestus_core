# Side-Effects e Crash Recovery — Pesquisa

> Pesquisa realizada em 2026-04-04 comparando Temporal.io e Sage (Elixir) para informar decisões futuras sobre rastreamento de side-effects no Hephaestus.

## O Problema

Quando um step tem múltiplos side-effects (cobrar cliente, enviar email, criar task externa) e o processo morre no meio da execução, como saber quais side-effects já foram executados para evitar duplicação no recovery?

```
step execute:
  side-effect 1: cobrar cliente    ✅ executou
  side-effect 2: enviar email      ✅ executou
  side-effect 3: criar task        ❌ crash aqui
  
recovery → re-executa step → cobra cliente de novo, manda email de novo
```

---

## Temporal.io

### Modelo

Temporal usa **event sourcing** com um Event History persistido no servidor (Cassandra/PostgreSQL). Cada ação no workflow gera um evento imutável.

### Como rastreia side-effects

- **Activities** são unidades atômicas — Temporal NÃO rastreia sub-steps dentro de uma Activity
- `workflow.SideEffect()` grava um `MarkerRecorded` no Event History. No replay, retorna o valor gravado sem re-executar
- Se uma Activity crashar no meio, ela é **re-executada do início** na próxima tentativa

### Heartbeat — checkpoint manual dentro de uma Activity

Para Activities longas com múltiplas operações, o developer usa `RecordHeartbeat(ctx, progress)` para salvar progresso no servidor. No retry, `GetHeartbeatDetails(ctx)` recupera o último checkpoint:

```go
func ProcessLargeFileActivity(ctx context.Context, params FileParams) error {
    startIdx := 0
    if activity.HasHeartbeatDetails(ctx) {
        var lastProcessed int
        activity.GetHeartbeatDetails(ctx, &lastProcessed)
        startIdx = lastProcessed + 1
    }
    for i := startIdx; i < params.TotalChunks; i++ {
        processChunk(params.FileURL, i)
        activity.RecordHeartbeat(ctx, i)  // checkpoint
    }
    return nil
}
```

### Idempotência

- Garantia: **at-least-once** (Activity pode executar mais de uma vez)
- Developer usa `workflowRunId + activityId` como idempotency key
- Fórmula: `at-least-once (Temporal) + idempotent Activity (developer) = effectively exactly-once`

```go
func ChargeCustomerActivity(ctx context.Context, amount int64) (string, error) {
    info := activity.GetInfo(ctx)
    key := fmt.Sprintf("%s-%d", info.WorkflowExecution.RunID, info.Attempt)
    charge, err := stripeClient.Charges.New(&stripe.ChargeParams{
        Amount: stripe.Int64(amount),
    }, stripe.WithIdempotencyKey(key))
    return charge.ID, err
}
```

### Trade-offs

- Workflow code deve ser **determinístico** (sem time.Now(), rand, IO direto)
- SideEffect não tem error handling — se falhar, re-executa sem garantias
- Event History tem limite de 50MB / 51,200 eventos
- Infraestrutura pesada: servidor próprio, persistence layer, cluster
- Replay pode ser lento para workflows muito longos

### Recomendação do Temporal

Dividir em Activities granulares. Cada Activity tem um side-effect. Activities grandes com múltiplos efeitos usam Heartbeat para checkpoint.

---

## Sage (Elixir)

### Modelo

Sage implementa o **Saga pattern** — cada step é uma transação + compensação. Execução forward, compensação backward em ordem reversa.

### Como rastreia side-effects

- State vive **inteiramente in-memory** no processo chamador
- `effects_so_far` é um map `%{step_name => effect}` que acumula conforme steps completam
- Cada step produz **exatamente um efeito**
- NÃO tem conceito de sub-efeitos dentro de um step
- NÃO tem persistência — crash do processo = perde tudo

### Pipeline e compensação

```elixir
Sage.new()
|> Sage.run(:reserve_inventory, &reserve/2, &release_reservation/3)
|> Sage.run(:charge_payment, &charge/2, &refund_payment/3)
|> Sage.run(:create_db_record, &insert_order/2, &delete_order/3)
|> Sage.run(:send_confirmation, &send_email/2, :noop)
|> Sage.execute(attrs)
```

Se `:charge_payment` falhar, Sage executa `release_reservation/3` (compensação reversa).

### Retry

Retries são triggered pela **compensação**, não pela transação:

```elixir
def compensate_charge(charge, _effects, _attrs) do
  Stripe.refund(charge.id)
  {:retry, [retry_limit: 5, base_backoff: 50]}
end
```

### Patterns úteis

- **Circuit breaker**: compensação retorna `{:continue, cached_value}` para usar fallback
- **Abort**: `{:abort, reason}` pula todos os retries e vai direto pra compensação
- **Ecto integration**: `Sage.transaction(Repo, attrs)` wrapa tudo em transação DB

### Trade-offs

- **Zero persistência**: crash = perde tudo (limitação explícita da lib)
- **Sem forward recovery**: só compensa backward, não retoma
- **Sem compensação paralela**: sempre sequencial reversa
- **Contador de retry global**: compartilhado entre todos os steps
- **In-process blocking**: retries com backoff bloqueiam o processo

### Recomendação do Sage

Cada step deve ter **um** side-effect. Steps com múltiplos efeitos devem ser divididos. Compensações devem ser idempotentes.

---

## Comparativo

| | **Temporal** | **Sage** | **Hephaestus (atual)** |
|---|---|---|---|
| Persistência | Event History (servidor) | Zero (in-memory) | Storage (ETS/futuro Ecto) |
| Unidade de rastreamento | Activity (atômica) | Step (atômico) | Step (atômico) |
| Sub-efeitos por unidade | Não rastreia (usa Heartbeat) | Não suporta | Não suporta |
| Crash recovery | Replay do Event History | Sem recovery | Recovery do Storage |
| Compensação | Manual (developer) | Automática (backward) | Não tem |
| Idempotência | Developer (idempotency key) | Developer | Developer |
| Retry | RetryPolicy automático | Via compensação | Não tem (MVP) |

---

## Decisão pro Hephaestus

### MVP (atual)

1. **Steps devem ser granulares** — um side-effect por step
2. **Storage persiste após cada complete_step** — já implementado
3. **Recovery retoma de active_steps** — step que crashou mid-execution é re-executado (at-least-once)
4. **Idempotência é responsabilidade do step** — documentar
5. **Sem compensação automática** — escopo de fase futura

### Futuro (a considerar)

- **Compensação (Saga pattern)**: cada step declara `compensate/3` opcional. No failure, executa compensações em ordem reversa. Inspirado no Sage
- **Effect tracking**: conceito de effects declarados dentro de um step, com checkpoint entre eles. Inspirado no Heartbeat do Temporal
- **Retry policy**: configurável por step (max_attempts, backoff). Phase 2 no PRD
- **Idempotency key**: engine gera `instance_id + step_ref + attempt` como key estável pra steps usarem

---

## Fontes

### Temporal
- [Side Effects - Go SDK](https://docs.temporal.io/develop/go/side-effects)
- [Failure detection - Go SDK](https://docs.temporal.io/develop/go/failure-detection)
- [Activity Execution](https://docs.temporal.io/activity-execution)
- [What Is Idempotency? | Temporal Blog](https://temporal.io/blog/idempotency-and-durable-execution)

### Sage
- [GitHub: Nebo15/sage](https://github.com/Nebo15/sage)
- [Hex.pm: sage](https://hex.pm/packages/sage)
