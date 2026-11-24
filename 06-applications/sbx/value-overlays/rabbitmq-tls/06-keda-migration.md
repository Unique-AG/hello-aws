# KEDA: scale on Prometheus, not the management API

`TriggerAuthentication/rabbitmqcluster-chat-unique-user` takes `host_full` from
the default-user secret — a management-API URL with the password inline. It has
to be deleted in the **same step** as the broker swap, not after it, because the
step that disables plaintext access also takes away the credential that URL
carries. The README's step 6 says the same.

## What the triggers do today

Three `ScaledObject`s use the `TriggerAuthentication`, not one. They do not share
a target, so the move has to be made per object rather than once:

| `ScaledObject` | Queue | `value` | Replicas |
|---|---|---|---|
| `backend-service-ingestion-worker` | `unique.node.ingestion.queue` | `"0.9"` | 0–12 |
| `backend-service-ingestion-worker-chat` | `unique.node.ingestion.chat_queue` | `"0.9"` | 0–12 |
| `ingestor` | `unique.node.ingestion.queue` | `"5"` | 1–6 |

Each has the same shape:

```yaml
triggers:
  - type: rabbitmq
    metadata:
      protocol: http
      mode: QueueLength
      queueName: unique.node.ingestion.queue
      value: "0.9"
    authenticationRef:
      name: rabbitmqcluster-chat-unique-user
```

Two of them watch the same queue with different targets. That is how it runs
today; the migration preserves it rather than reconciling it.

Sources: `sbx/apps/chat/ingestion-worker.backend-service.yaml`,
`sbx/apps/chat/ingestion-worker-chat.backend-service.yaml`, and
`defaults/ai-services/ingestor.yaml`, which is rendered through
`sbx/apps/chat/ingestor.yaml`.

## The replacement

```yaml
triggers:
  - type: prometheus
    metadata:
      serverAddress: http://kube-prometheus-stack-prometheus.unique.svc:9090
      query: sum(rabbitmq_queue_messages_ready{queue="<queue>"})
      threshold: "<the value: from the table above>"
      activationThreshold: "0"
```

`threshold` takes the `value:` of the object being moved — `"0.9"` for the two
backend services, `"5"` for `ingestor`. The two are not interchangeable: KEDA
divides the metric by the threshold, so `"1"` in place of `"0.9"` asks for
`ceil(n/1)` replicas where the queue trigger asked for `ceil(n/0.9)`, and the
worker scales about ten percent later than it does now.

`activationThreshold` is what lets an object leave zero replicas, and a
`prometheus` trigger needs it stated where the `rabbitmq` trigger did not. It
applies to the two backend services. `ingestor` has `minReplicaCount: 1` and
never scales to zero, so it does not need one.

## Prerequisite

`prometheus.return_per_object_metrics = true` is set by whichever broker file is
live: `broker/rabbitmqcluster-transitional.yaml` from README step 4, and
`broker/rabbitmqcluster-hardened.yaml` from step 6.
Without it the exporter publishes only aggregates, the per-queue series in the
query above does not exist, and the query returns empty — which KEDA reads as
zero load and scales the worker to nothing. Confirm the series is present before
switching any `ScaledObject` over.

No `TriggerAuthentication` replaces the old one: in-cluster Prometheus needs no
credential, so this is a deletion rather than a swap.
