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
| `04-users-and-permissions.yaml` | An import secret, a passwordless `User` named after the certificate's common name, and a `Permission`, one set per service |
| `05a-rabbitmqcluster-transitional.yaml` | The broker with a TLS listener added and nothing removed, so certificate login can be proved while passwords still work |
| `05-rabbitmqcluster-tls.yaml` | The hardened broker: TLS-only listeners, `EXTERNAL` auth, per-queue metrics |
| `06-keda-migration.md` | How KEDA moves to Prometheus metrics instead of the management API |

## Turning it on

In this order, so no step removes a credential a caller is still using:

1. Ship the AMQP package release that can present a client certificate, and set
   each service to use it.
2. Apply `01`–`04`. The new users exist alongside `app`; nothing changes yet.
3. Apply `05a-rabbitmqcluster-transitional.yaml`. This adds a TLS listener and
   `EXTERNAL` **alongside** passwords, and leaves plaintext open. The live
   broker has no `spec.tls` at all, so without this there is nothing to test
   certificate login against and the cutover would be its own first test.
4. **Prove certificate login, service by service.** Open a real `amqps`
   connection presenting the client certificate and confirm the broker reports
   the user named by its common name. `rabbitmqctl authenticate_user` does not
   prove this — it tests passwords. A common name that matches no user is
   refused, and at this point that costs nothing because passwords still work.
5. **Give the Messaging Topology Operator the broker CA.** After step 6 the
   management API serves HTTPS only, and the operator must trust
   `rabbitmq-ca-tls` to reach it. It runs in `unique`, the same namespace the CA
   Secret is created in. Without this, `User` and `Permission` reconciliation
   stops — including for the users this directory creates.
6. Replace `../rabbitmq/rabbitmq-cluster.yaml` with `05-rabbitmqcluster-tls.yaml`,
   and in the same change delete
   `TriggerAuthentication/rabbitmqcluster-chat-unique-user` and move the
   `ScaledObject`s onto Prometheus per `06-keda-migration.md`. They belong
   together: this step disables the plaintext listener that the
   `TriggerAuthentication` URL depends on.
7. **Replace the operator's administrator, then delete `app`.** The broker's
   default user is `app`, and the Messaging Topology Operator authenticates as
   it — deleting it first would stop the operator reconciling anything. Create a
   replacement administrator, point the cluster's default-user binding at it,
   confirm a topology resource still reconciles, and only then remove `app`.
   Step 6 does not remove it; it only stops password logins over AMQP.

To switch on, add an app file under `06-applications/sbx/apps/chat/` whose
`spec.source.path` is this directory. That one file is the switch.

## Not settled

- **The management API stays enabled.** The cluster operator writes
  `enabled_plugins` itself and always includes `rabbitmq_management`, so it
  cannot be dropped by choosing a plain image — that would point the node at a
  plugin it does not ship. Its HTTP listener authenticates separately from AMQP,
  so `EXTERNAL` does not close it. Removing or restricting it is unresolved.
- **The default user is `app`, and the Messaging Topology Operator depends on
  it.** Anything that removes or renames it has to provide the operator another
  administrator first, which is why that is its own step above.
- The cluster operator's own default user and the Erlang cookie still use the
  secret backend. Both are internal to the operator; how they are handled on a
  Marketplace installation is an open question.
- The import secret is read once, when the user is created. The operator does
  not watch it, so editing one later does not rotate anything.
- Three replicas across three zones and quorum queues belong with the RabbitMQ 4
  move, not here.
