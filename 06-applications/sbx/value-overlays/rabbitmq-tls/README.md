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
| `04-users-and-permissions.yaml` | An import secret, a `User` and a `Permission` per service. An empty `passwordHash` makes the user passwordless, so its certificate is the only way in |
| `broker/rabbitmqcluster-transitional.yaml` | The broker with TLS added and nothing removed, so certificate login can be proved while passwords still work |
| `broker/rabbitmqcluster-hardened.yaml` | The end state: TLS-only listeners, `EXTERNAL` auth, per-queue metrics |
| `06-keda-migration.md` | How KEDA moves to Prometheus metrics instead of the management API |

Both broker files pin the image by digest with the `3.13-management` tag kept in
front of it, so Renovate still tracks the version. The digest is the one the live
broker already runs, so replacing the manifest changes configuration only. The
live manifest keeps its bare tag until one of these replaces its body.

### Why `broker/` is separate

Both files under `broker/` declare the same `RabbitmqCluster`
(`unique/rabbitmqcluster-chat`), and so does the live
`../rabbitmq/rabbitmq-cluster.yaml`. An Application reading a directory that
contained two of them would silently keep whichever sorted last and warn with
`RepeatedResourceWarning` — which, before this split, meant the *transitional*
broker would have won and left plaintext enabled.

They are not applied from here. Each is a replacement for the body of
`../rabbitmq/rabbitmq-cluster.yaml`, committed to Git at the step that calls for
it. The Application that owns that path runs with `selfHeal: true`, so a change
made by hand is reverted; going through Git is what makes it stick.

An Application added for this directory must therefore set
`directory.exclude: 'broker/**'`, or it will fight the one that already owns the
broker.

## Turning it on

In this order, so no step removes a credential a caller is still using:

1. Ship the AMQP package release that can present a client certificate, and set
   each service to use it.
2. Apply `01`–`04`. The new users exist alongside `app`; nothing changes yet.
3. **Give the Messaging Topology Operator the broker CA**, before any TLS is
   enabled on the cluster. Enabling `spec.tls` in the next step also opens the
   HTTPS management port, and the operator prefers it — so from step 4 onward it
   needs to trust `rabbitmq-ca-tls` or `User` and `Permission` reconciliation
   fails certificate verification. The operator runs in `unique`, the namespace
   `01` creates the CA Secret in.
4. Commit `broker/rabbitmqcluster-transitional.yaml` over
   `../rabbitmq/rabbitmq-cluster.yaml`. This adds a TLS listener and `EXTERNAL`
   **alongside** passwords and leaves plaintext open. The live broker has no
   `spec.tls` at all, so without this there is nothing to test certificate login
   against and the cutover would be its own first test.
5. **Prove certificate login, service by service.** Open a real `amqps`
   connection presenting the client certificate and confirm the broker reports
   the user named by its common name. `rabbitmqctl authenticate_user` does not
   prove this — it tests passwords. A common name that matches no user is
   refused, and at this point that costs nothing because passwords still work.
6. Commit `broker/rabbitmqcluster-hardened.yaml` over
   `../rabbitmq/rabbitmq-cluster.yaml`, and in the same change delete
   `TriggerAuthentication/rabbitmqcluster-chat-unique-user` and move all three
   `ScaledObject`s that reference it — `backend-service-ingestion-worker`,
   `backend-service-ingestion-worker-chat` and `ingestor` — onto Prometheus per
   `06-keda-migration.md`. They belong together: this step disables the
   plaintext listener that the `TriggerAuthentication` URL depends on, and each
   object carries its own target.
7. **Replace the operator's administrator, then delete `app`.** The broker's
   default user is `app`, and the Messaging Topology Operator authenticates as
   it — deleting it first would stop the operator reconciling anything. Create a
   replacement administrator, point the cluster's default-user binding at it,
   confirm a topology resource still reconciles, and only then remove `app`.
   Step 6 does not remove it; it only stops password logins over AMQP.

To switch on, add an app file under `06-applications/sbx/apps/chat/` whose
`spec.source.path` is this directory and which excludes `broker/**`. That one
file is the switch.

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
- **Permissions are wide.** Each `Permission` grants full configure, write and
  read on `/`. Narrowing them per service is unresolved.
- The import secret is read once, when the user is created. The operator does
  not watch it, so editing one later does not rotate anything.
- Three replicas across three zones and quorum queues belong with the RabbitMQ 4
  move, not here.
