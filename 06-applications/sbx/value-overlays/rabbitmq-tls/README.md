# RabbitMQ certificate sign-in (prepared, not switched on)

Nothing here is applied. No ArgoCD Application points at this directory, and the
ApplicationSet that builds the chat apps globs `06-applications/sbx/apps/chat/*.yaml`
only — so these manifests are inert until someone adds an app file for them.

## Why it is off

The brokers keep running in-cluster on AWS installations and move from a single
shared password to per-service TLS client certificates (SASL `EXTERNAL`). The
client half of that lands in the shared AMQP package as an optional sign-in mode,
off by default; the owning team and date are not set. Turning this on before the
services can present a certificate would lock every caller out of the broker, so
it waits for the product release.

## What is here

| File | What it creates |
|---|---|
| `01-certificate-authority.yaml` | A self-signed root, a CA certificate, and the CA issuer the rest use |
| `02-server-certificate.yaml` | The broker's server certificate, with the in-cluster service names as SANs |
| `03-client-certificates.yaml` | One client certificate per service; the common name is the RabbitMQ user name |
| `04-users-and-permissions.yaml` | Passwordless `User` and `Permission` objects, one per service |
| `05-rabbitmqcluster-tls.yaml` | The hardened broker: TLS only, `EXTERNAL`, no management plugin |
| `06-keda-trigger-authentication.yaml` | KEDA scaling on Prometheus metrics instead of the management API |

## Turning it on

In this order, so no step removes a credential a caller is still using:

1. Ship the AMQP package release that can present a client certificate, and set
   each service to use it.
2. Apply `01`–`04`. The new users exist alongside `app`; nothing changes yet.
3. Point the services at their certificates and confirm each one connects.
4. Replace `../rabbitmq/rabbitmq-cluster.yaml` with `05-rabbitmqcluster-tls.yaml`.
   This is the step that closes the plaintext listener and drops the `app` user.
5. Apply `06` and delete the old `TriggerAuthentication`, which reads the
   management API that step 4 removed.

To switch on, add an app file under `06-applications/sbx/apps/chat/` whose
`spec.source.path` is this directory. That one file is the switch.

## Not settled

- The cluster operator's own default user and the Erlang cookie still use the
  secret backend. Both are internal to the operator; how they are handled on a
  Marketplace installation is an open question.
- Three replicas across three zones and quorum queues belong with the RabbitMQ 4
  move, not here.
