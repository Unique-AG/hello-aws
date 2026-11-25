# Observability baseline

What is scraped, what is not, and why. The companion to `security-baseline.md`:
an entry here is a decision with a reason, not a reminder to do something later.

Every row was measured against the running sandbox, not inferred from values
files. Where a measurement contradicted the configuration, the measurement won.

## What most workloads have regardless

Prometheus scrapes `kubelet`/cAdvisor and `kube-state-metrics`, so a pod on an
EC2 node has CPU, memory, restarts, phase and scheduling metrics whether or not
it has a monitor of its own. Grafana also reads CloudWatch, which carries the
load balancers, EKS and the managed data stores.

So "it has metrics in Grafana" and "its own metrics are scraped" are different
claims. This document is about the second.

**The exception is Fargate.** All three kubelet scrapes for the Fargate node
report `up == 0`, because Fargate runs the kubelet inside the microVM where
Prometheus cannot reach it. Pods there — today the Conduct sandbox pool in
namespace `sbx` — therefore have **no container CPU or memory series**.
`kube-state-metrics` still reports their phase and restarts, since it reads the
API server rather than the node, and CloudWatch still sees the task. Do not
assume a sandbox pod's resource usage is in Prometheus; it is not.

## Application endpoints that are scraped

| Workload | Endpoint | Monitor |
|---|---|---|
| Qdrant | `:6333/metrics` | chart's own ServiceMonitor (`metrics.serviceMonitor.enabled`) |
| RabbitMQ | `:15692/metrics` | `value-overlays/rabbitmq/service-monitor.yaml` |
| backend-service-speech | `:8080/metrics` | chart ServiceMonitor, via `prometheus.enabled` |
| chat, ingestion, configuration, scope-management, app-repository | chart default | chart ServiceMonitor |
| assistants-core | chart default | chart ServiceMonitor |

The endpoint column is a measurement taken from inside the cluster. The monitor
column is configuration: a row added by this change has a reachable endpoint but
no `up` series until ArgoCD syncs it, so verify with `up{job=~"qdrant|rabbitmq.*"}`
after the sync rather than reading the table as proof of a live target.

RabbitMQ needs its own manifest because the cluster is operator-managed and has
no chart values to set. Its metrics matter beyond dashboards: the KEDA migration
in `sbx/value-overlays/rabbitmq-tls/06-keda-migration.md` moves the ingestion
scalers from the AMQP trigger to `rabbitmq_queue_messages_ready`, which did not
exist in Prometheus before this.

## The two Prometheus switches are not interchangeable

The `backend-service` chart gates on both, and they do different things:

- `prometheus.enabled: false` removes the ServiceMonitor **and all four default
  alert rule sets** — ArgoCD, kubernetes-application, kubernetes-resources and
  custom.
- `prometheus.scraping.enabled: false` removes only the monitor and keeps the
  alerts.

Most of those alerts — `KubePodCrashLooping`, `KubernetesContainerOOMKilled`,
`KubePodNotReady`, `ArgoCDApplicationDegraded` — are computed from
kube-state-metrics and need no `/metrics` endpoint at all. So a service without
one still wants `enabled: true`. Reach for `scraping.enabled: false` instead;
`enabled: false` is only right if the service should not alert either.

## Exceptions

Each was measured on the service's real port, not assumed.

| Workload | Port | Result | Why it is an exception |
|---|---|---|---|
| LiteLLM | `:4000` | 404 on `/metrics` and `/prometheus` | The OSS build serves no Prometheus endpoint; it is a licensed feature. |
| ingestor | `:80` | 404 on `/metrics` and `/actuator/prometheus` | Serves no metrics endpoint. It does emit `pino-json` logs, which Alloy parses. |
| backend-service-event-socket | `:8080` | 404 on `/metrics` | HTTP server, no metrics endpoint. Alerts kept via `scraping.enabled: false`. |
| backend-service-webhook-scheduler | `:8080` | ECONNREFUSED | Worker with no HTTP listener, despite a declared port and a Service. |
| backend-service-webhook-worker | `:8080` | ECONNREFUSED | As above. |
| web-app-admin / -chat / -knowledge-upload / -theme | `:3000` | 404 on `/metrics` | Front ends with no metrics endpoint. |

Revisit LiteLLM if the deployment moves to a licensed build, and the web apps if
they gain an instrumentation endpoint.

## Absent but correct

Recorded because they look like gaps in a target list and are not.

- **`backend-service-ingestion-worker` and `-ingestion-worker-chat`** have valid
  ServiceMonitors whose selectors match their Services, but no `up` series.
  KEDA holds both Deployments at 0 replicas while their queues are idle
  (`minReplicaCount: 0`, RabbitMQ trigger), so there is no pod to scrape. The
  series appears when work does.

## Known gaps

Unresolved rather than decided, and recorded so they are not mistaken for either.

- **`client-insights-exporter` produces no target.** Its PodMonitor selector does
  match the pod labels, but the workload is a CronJob, so the only matching pod
  is a `Completed` one. Between runs there is nothing to scrape, and a run is
  unlikely to outlive a 30s scrape interval. A push to a Pushgateway, or an
  exporter that runs continuously, would be needed to capture it.

## Tracing

`OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` must be set explicitly: unset, the exporter
defaults to `localhost:4318` and every span is dropped. It is set for all twelve
backend services in `backend-services/_all.yaml`, and for assistants-core in its
own overlay.

Whether a service should get it is decided by looking in the image, not by what the
service does. assistants-core carries 13 OpenTelemetry distributions, including
`opentelemetry-exporter-otlp-proto-http` and the FastAPI and requests
instrumentation, so the endpoint is what it was missing. **ingestor carries zero**,
so setting the variable there would be cosmetic — it is on the exception list below
until the image is instrumented.

| Workload | OpenTelemetry distributions in the image | Outcome |
|---|---|---|
| assistants-core | 13, incl. the OTLP HTTP exporter | endpoint set |
| ingestor | 0 | exception — not instrumented |

## Log format

Alloy parses exactly one format. Its `stage.match` selector is
`{logging_unique_app_format="pino-json"}`, and the stage extracts pino's own fields
(`msg`, `level`, `operationName`, `req`). There is no second format stage, so a
service whose logs are structured but not pino has nowhere to go: labelling it
`pino-json` would make Alloy extract keys that do not exist, which is worse than
leaving it unlabelled.

Carrying the label today: every backend service, ingestor, client-insights-exporter,
data-redaction-task, expired-content-deletion and user-sync. It comes from the
Unique chart.

| Workload | Measured log shape | Why it has no label |
|---|---|---|
| assistants-core | 25/25 sampled lines parse as JSON, **0** pino-shaped | Structured, but not pino. Needs a second Alloy stage for its schema, not this label. |
| web-app-admin / -chat / -knowledge-upload / -theme | 0/5 sampled lines parse as JSON | Plain text; nothing to parse. |
| Qdrant, RabbitMQ, LiteLLM | — | Third-party charts; their logs are not pino JSON. |

assistants-core is the one worth revisiting: its logs are already machine-readable
and are being shipped to Loki as opaque lines.
