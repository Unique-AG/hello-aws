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
| `05-rabbitmqcluster-tls.yaml` | The hardened broker: TLS-only listeners, `EXTERNAL` auth, per-queue metrics |
| `06-keda-migration.md` | How KEDA moves to Prometheus metrics instead of the management API |

## Turning it on

In this order, so no step removes a credential a caller is still using:

1. Ship the AMQP package release that can present a client certificate, and set
   each service to use it.
2. Apply `01`–`04`. The new users exist alongside `app`; nothing changes yet.
3. Point the services at their certificates and confirm each one connects.
4. **Prove certificate login works before taking plaintext away.** With the
   broker still accepting passwords, enable `rabbitmq_auth_mechanism_ssl` and
   check that each service authenticates as the user named by its certificate —
   `rabbitmqctl authenticate_user` will not do it, because it tests passwords.
   A real `amqps` connection presenting the client certificate is the only
   proof. If a common name does not match a user, the login is refused and that
   service stops working the moment step 5 lands.
5. Replace `../rabbitmq/rabbitmq-cluster.yaml` with `05-rabbitmqcluster-tls.yaml`,
   and in the same change delete `TriggerAuthentication/rabbitmqcluster-chat-unique-user`
   and move the `ScaledObject`s onto Prometheus per `06-keda-migration.md`. They
   belong together: this step disables the plaintext listener, which is what
   that `TriggerAuthentication`'s URL depends on.
6. Delete the `app` user. Step 5 does not remove it — it only stops password
   logins over AMQP — so it has to go explicitly once nothing uses it.

To switch on, add an app file under `06-applications/sbx/apps/chat/` whose
`spec.source.path` is this directory. That one file is the switch.

## Not settled

- **The management API stays enabled.** The cluster operator writes
  `enabled_plugins` itself and always includes `rabbitmq_management`, so it
  cannot be dropped by choosing a plain image — that would point the node at a
  plugin it does not ship. Its HTTP listener authenticates separately from AMQP,
  so `EXTERNAL` does not close it. Removing or restricting it is unresolved.
- The cluster operator's own default user and the Erlang cookie still use the
  secret backend. Both are internal to the operator; how they are handled on a
  Marketplace installation is an open question.
- The import secret is read once, when the user is created. The operator does
  not watch it, so editing one later does not rotate anything.
- Three replicas across three zones and quorum queues belong with the RabbitMQ 4
  move, not here.
