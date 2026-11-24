# KEDA: scale on Prometheus, not the management API

`TriggerAuthentication/rabbitmqcluster-chat-unique-user` takes `host_full` from
the default-user secret — a management-API URL with the password inline. It has
to be deleted in the **same step** as the broker swap, not after it, because the
step that disables plaintext access also takes away the credential that URL
carries. The README's step 6 says the same.

## What the trigger does today

```yaml
triggers:
  - type: rabbitmq
    metadata:
      protocol: http
      mode: QueueLength
      queueName: unique.node.ingestion.queue
      value: "0.9"            # target ≈ one message per replica
    authenticationRef:
      name: rabbitmqcluster-chat-unique-user
```

with `minReplicaCount: 0` and `maxReplicaCount: 12`.

## The replacement

```yaml
triggers:
  - type: prometheus
    metadata:
      serverAddress: http://kube-prometheus-stack-prometheus.unique.svc:9090
      query: sum(rabbitmq_queue_messages_ready{queue="unique.node.ingestion.queue"})
      threshold: "1"          # keeps the ≈ one-message-per-replica target
      activationThreshold: "0"
```

`threshold` carries over the `value: 0.9` target, not an arbitrary number —
raising it would make the worker scale later than it does now.
`activationThreshold` is what lets it leave zero replicas; a `prometheus`
trigger needs it stated, whereas the `rabbitmq` trigger did not.

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
