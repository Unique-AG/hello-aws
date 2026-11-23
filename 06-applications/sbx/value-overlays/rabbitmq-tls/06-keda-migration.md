# KEDA: scale on Prometheus, not the management API

Step 4 of the README removes the management plugin, which is what
`TriggerAuthentication/rabbitmqcluster-chat-unique-user` reads. That object takes
`host_full` from the default-user secret — a URL with the password inline — so it
has to go in the same step, not after it.

Every `ScaledObject` scaling on this broker moves from a `rabbitmq` trigger to a
`prometheus` one:

```yaml
triggers:
  - type: prometheus
    metadata:
      serverAddress: http://kube-prometheus-stack-prometheus.unique.svc:9090
      query: sum(rabbitmq_queue_messages_ready{queue="<queue>"})
      threshold: "100"
```

The `rabbitmq_prometheus` plugin stays enabled in `05-rabbitmqcluster-tls.yaml`
and serves these metrics on port 15692. In-cluster Prometheus needs no
credential, so no replacement `TriggerAuthentication` is required — this is a
deletion, not a swap.

Per-object queue metrics need `prometheus.return_per_object_metrics = true` in
the broker config if the queue-level series are not already exported.
