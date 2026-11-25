# Observability baseline

What is scraped, what is not, and why. The companion to `security-baseline.md`:
an entry here is a decision with a reason, not a reminder to do something later.

## What every workload has regardless

Prometheus scrapes `kubelet`/cAdvisor and `kube-state-metrics`, so **every pod**
has CPU, memory, restarts, phase and scheduling metrics whether or not it has a
monitor of its own. Grafana also reads CloudWatch, which carries the load
balancers, EKS and the managed data stores.

So "it has metrics in Grafana" and "its own metrics are scraped" are different
claims. This document is about the second.

## Application endpoints that are scraped

| Workload | Endpoint | Monitor |
|---|---|---|
| Qdrant | `:6333/metrics` | chart's own ServiceMonitor (`metrics.serviceMonitor.enabled`) |
| RabbitMQ | `:15692/metrics` | `value-overlays/rabbitmq/service-monitor.yaml` |
| Backend services | chart default | ServiceMonitor from the chart |
| assistants-core | chart default | ServiceMonitor from the chart |

RabbitMQ needs its own manifest because the cluster is operator-managed and has
no chart values to set. Its metrics matter beyond dashboards: the KEDA migration
in `sbx/value-overlays/rabbitmq-tls/06-keda-migration.md` scales on
`rabbitmq_queue_messages_ready`, which did not exist in Prometheus before this.

## Exceptions

Each was measured on the service's real port, not assumed.

| Workload | Port | Result | Why it is an exception |
|---|---|---|---|
| LiteLLM | `:4000` | 404 on `/metrics` and `/prometheus` | The OSS build does not serve a Prometheus endpoint; it is a licensed feature. Nothing to scrape. |
| ingestor | `:80` | 404 on `/metrics` and `/actuator/prometheus` | Serves no metrics endpoint. It does emit `pino-json` logs, which Alloy parses. |
| web-app-admin | `:3000` | 404 on `/metrics` | Front end with no metrics endpoint. |
| web-app-chat | `:3000` | 404 on `/metrics` | As above. |
| web-app-knowledge-upload | `:3000` | 404 on `/metrics` | As above. |
| web-app-theme | `:3000` | 404 on `/metrics` | As above. |

Revisit LiteLLM if the deployment ever moves to a licensed build, and the web
apps if they gain an instrumentation endpoint.

## Log format

Alloy applies JSON parsing to pods labelled `logging.unique.app/format: pino-json`
and passes everything else through as plain lines. The label comes from the
Unique chart, so services on third-party charts do not have it — which is correct
for them, since their logs are not pino JSON.

## Known gaps, not exceptions

These are unresolved rather than decided, and are recorded so they are not
mistaken for either.

- **Four backend services have no monitor**: `event-socket`, `speech`,
  `webhook-scheduler`, `webhook-worker`. The others get one from the same chart,
  so this looks like configuration rather than intent.
- **`client-insights-exporter`'s PodMonitor produces no target.** It selects
  `app.kubernetes.io/component: server`, but the workload runs as a CronJob, so
  there is no steady pod for it to match.
