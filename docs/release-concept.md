# Release Concept

How a Unique platform release becomes a running deployment in your fork of `hello-aws`,
and how you keep one or more environments up to date over time.

`hello-aws` is **trunk-based**. One `main` branch is the source of truth and the
**environment template**; one long-lived **`deploy`** branch holds the real, per-environment
configuration as one folder per environment. Updates always flow **forward** (`main` →
`deploy`).

A **release** is a Git tag on `main` (`202X.XX.X`) that names a complete, immutable set of
component versions and configuration, **published as a
[GitHub Release](https://github.com/Unique-AG/hello-aws/releases)** with notes describing
what changed and any newly-required configuration. The tag is the identity; the GitHub
Release is its published, human-facing wrapper — and what you watch to learn a new version is
available.

Each environment **adopts** a release independently — so different environments can run
different releases (e.g. `sbx` on a new release while `prod` stays on the previous one until
it is validated). Deploying is advancing an environment's folder to the release it adopts and
pushing.

---

## At a glance

| | |
|---|---|
| **Trunk** | `main` — source of truth and **environment template**; CI-gated; carries release content (versions + `defaults/`) but no environment-specific values |
| **Deploy branch** | a long-lived `deploy` branch holding each environment's real values — **suggested layout:** one folder per environment (`sbx/`, `prod/`, …); per-environment branches work too |
| **Release** | a Git tag `202X.XX.X` on `main`, **published as a GitHub Release** with notes — the *only* place a release version exists |
| **Per-environment version** | each environment **adopts** a release tag independently → environments can run **different releases** (staged rollout: `sbx` → validate → `prod`) |
| **Flow direction** | always forward: `feat/*` → `main` → `deploy`. Never `deploy` → `main` |
| **Infrastructure (layers 01–05)** | Terraform — a push to `deploy` applies the layers for the changed environment |
| **Applications (layer 06)** | ArgoCD — watches the `deploy` branch and reconciles each environment's apps |
| **What varies** | three separate concerns — **version**, **release config**, **instance config** — each with its own home (see [Separating…](#separating-version-release-config-and-instance-config)) |

---

## Branching model

```
feat/* ─┐
fix/*  ─┤ squash PR (CI gates — see Quality gates)
chore/*┘
        ▼
      main ──tag 202X.22.0 → GitHub Release──►  trunk + environment template
        │                                       (release content: app specs + defaults/)
        │  adopt a release = merge its content into the env folder — forward only
        ▼
      deploy ──push──►  per-env Terraform apply (01–05) + ArgoCD reconcile (06)
        ├── sbx/    at 202X.22.0   (latest)
        └── prod/   at 202X.21.0   (until validated, then advances)
```

### `main` — trunk and environment template
- The single source of truth. All work lands via **squash-merged PRs**; CI gates every PR.
- Carries **release content** (the app specs and `defaults/`) and the **environment
  template** — the shape an environment instantiates. It holds **no** environment-specific
  values and **no** per-environment version pin.
- A **release** is a Git tag on `main`, published as a **GitHub Release** with notes. The tag
  is the only release-version string in the repository (see
  [Release identity](#release-identity-and-versioning)).

### `deploy` — the deployment branch
- A long-lived branch holding the real, per-environment configuration. **A push to `deploy` is
  a deployment** for the changed environment: Terraform applies its layers (01–05), and ArgoCD
  — watching `deploy` — reconciles its applications (layer 06).
- **Suggested layout: one `deploy` branch with one folder per environment** (`sbx/`, `prod/`,
  …), with ArgoCD pointing each cluster at its own folder. This is a recommendation, not a
  requirement — a **per-environment-branch** layout (`deploy/sbx`, `deploy/prod`) works equally
  well; pick whichever suits your access and review model.
- Each environment **adopts a release independently** by merging the release into its folder,
  so environments can sit on **different releases** (staged rollout).
- The `deploy` branch **diverges forward** from `main` and is never merged back; release
  content always originates on `main` and is brought in by adoption (see
  [How they compose](#how-they-compose)).

### Feature branches
`feat/*`, `fix/*`, `chore/*` → PR → squash-merge to `main`. PRs run the full validation
suite per layer. Applies happen only from a push to `deploy`, never from a PR.

---

## Quality gates (CI)

A release is only as trustworthy as the trunk it is cut from, so **every PR to `main` must
pass the gates below** before it can be squash-merged. Forks should keep these enabled.

**Per-layer checks** (`.github/workflows/tf.validate.yaml`, run for each Terraform layer):
- **Format** — `terraform fmt -check`
- **Validate** — `terraform init -backend=false` + `terraform validate`
- **Lint** — `tflint`
- **Security / IaC policy scanning** — `trivy` scans each layer's Terraform for
  misconfigurations and **fails the build on HIGH/CRITICAL**; `checkov` (3.x) runs the full
  Terraform policy set. Every suppression for both (`.trivyignore` and `checkov` skips) is
  documented with rationale in [`docs/security-baseline.md`](security-baseline.md) — the single
  source of truth for suppressions and sbx relaxations, reviewed toward a goal of zero.
- **Plan preview** — `terraform plan` posted as a PR comment (no apply on PRs)

**Repository-wide checks:**
- **Secret scanning** — push protection / pre-commit secret detection to keep credentials out
  of history
- **GitHub Advanced Security** — code scanning (CodeQL), dependency review, and Dependabot
  updates

Applies are never part of CI — they happen only on a push to the `deploy` branch (see
[The two delivery tracks](#the-two-delivery-tracks)).

---

## Separating version, release config, and instance config

Three kinds of content kept strictly apart, each changing for its own reason and flowing to
its own place. This is the core of the model.

| Concern | Examples | Changes when… | Lives in | On |
|---|---|---|---|---|
| **Version** | Helm chart version, `image.tag` | a new Unique **release** | the **app specs** (`apps/*.yaml`) | `main`, at each release tag |
| **Release config** | feature-flag defaults, env-var wiring, default resources, cron jobs, newly-*required* settings | a new **release** (config, not a version) | **`defaults/`** | `main`, at each release tag |
| **Instance config** | domains, ECR registry/account, Zitadel IDs, KMS keys, secret refs, model lists, theme/CSP, per-env sizing | a new **customer or environment** | **`<env>/value-overlays/`** | the `deploy` branch |

**Version** and **release config** together are the **release content** — defined once per
release on `main`, identical for every environment that adopts that release. *Which* release
an environment runs is recorded in its `deploy` folder (the tag it adopts), so environments
can differ.

> The instance-config folder is written `<env>/value-overlays/` throughout this document;
> current clones use `<env>/values/`.

### How they compose
ArgoCD generates one Application per service, reading the app specs (`<env>/apps/*.yaml`) and
all value files from the environment's folder on the `deploy` branch. The app specs are
**instance-free**: the Git reference they share (your fork's repo and the `deploy` branch) is
defined **once** in the ApplicationSet, not repeated per app.

Service values resolve by a **last-wins Helm merge** (lowest → highest priority):

```
defaults/<service>.yaml          (release config)
   └─ overridden by →
<env>/value-overlays/<service>   (instance config)
```

Both `defaults/` (release config) and `<env>/value-overlays/` (instance config) are read from
the `deploy` branch through a single shared `$values` source; component versions come from the
app specs in the env folder. **Adopting a release** brings the new release content (the
environment's `apps/` and `defaults/`) onto the `deploy` branch (see the runbook); your
`value-overlays/` stay as they are. `defaults/` is shared across environment folders, so a
release's `defaults/` apply to every environment once adopted — keep them backward-compatible
when environments run different releases.

### Configuration — the decision rule
> - Changes with a **Unique release** and the same for every customer?
>   → **`defaults/`** (ships on `main`; adopted with the tag).
> - A **customer/environment** choice, identity, or secret?
>   → **`<env>/value-overlays/`** (on the `deploy` branch).
> - A **version string** (chart or image)?
>   → the **app spec** (`apps/<service>.yaml`, adopted with the tag).

A release may introduce a **required** setting (for example, a feature flag a service needs
at startup, or a flag that must match between backend and frontend). Because such defaults
live in `defaults/` and are adopted with the tag, an environment gets them automatically when
it adopts the release — no manual discovery, and backend/frontend parity holds. Keep
`value-overlays/` limited to genuine per-environment overrides.

### Declaring instance values
`defaults/` declares the keys a service expects and marks the ones you must supply per
environment (e.g. `ADMIN_FRONTEND_URL: unset_default_value`). Your `<env>/value-overlays/`
provides the real values. A value you forget to set is visible as `unset_default_value`
rather than silently rendering an empty or placeholder string.

---

## Release identity and versioning

- **Release version.** A release is identified by its **Git tag** (`202X.XX.X`) on `main`,
  published as a **GitHub Release**.
- **GitHub Release.** The GitHub Release wraps the tag with human-facing notes — what changed,
  dependency upgrades, and any newly-required configuration — and is what consumers **watch**
  to learn a new version is available.
- **Component versions** (per-service chart version and image tag) live in the **app specs**
  under `06-applications/sbx/apps/`. Diff the versions between two releases:
  `git diff 202X.21.0 202X.22.0 -- 06-applications/sbx/apps`.
- **Per-environment version.** An environment's version is the release content in its
  `<env>/apps/` folder on `deploy`, advanced by merging a release. Environments can sit on
  different releases (different folder content).
- **Resource traceability.** Terraform stamps a `governance:SemanticVersion` tag on the
  resources it manages, derived in CI from `git describe --tags` on the `deploy` branch — so
  every AWS resource traces back to the release the branch currently carries.
- **Image registry.** Image *tags* are version content (in the app specs); the image *registry* (your
  ECR account) is instance content (`value-overlays` / common env config), composed at render
  time.

---

## The two delivery tracks

A push to `deploy` drives two independent mechanisms for the changed environment.

### Track 1 — Infrastructure (layers 01–05): Terraform
The layers apply in dependency order:

```
bootstrap (01) → governance (02) → infrastructure (03) → ┬→ data-and-ai (04)
                                                          └→ compute (05)
```

- Each layer assumes the deployment role via OIDC and runs `terraform apply` for the changed
  environment. State is per-layer, per-environment, in the shared S3 backend created by the
  bootstrap layer.
- Apply happens only for a push to the `deploy` branch; pull requests are plan/validate only.

### Track 2 — Applications (layer 06): ArgoCD
- ArgoCD runs in the cluster and watches the `deploy` branch. An ApplicationSet generates one
  Application per service from that environment's folder, reading **release content at the tag
  the environment adopts** and **instance config from the `deploy` branch** (see
  [How they compose](#how-they-compose)).
- Applications are reconciled when the environment's folder on `deploy` advances.

---

## How a release flows

1. **Cut on `main`** — bump the chart + image versions in the affected app specs
   (`apps/*.yaml`) and update `defaults/` for any new or newly-required release config, and the
   Terraform module/provider versions for the release. Open a PR; CI gates it; squash-merge.
2. **Tag and publish** — tag the merge commit `202X.XX.X` and publish the GitHub Release with
   notes. This is the release.
3. **Adopt per environment** — set the environment's adopted release tag (see
   [Part B](#part-b--adopt-a-release-in-an-environment-on-deploy)) and supply any new instance
   values in `<env>/value-overlays/`, then push. The Terraform pipeline applies that
   environment's infrastructure; ArgoCD reconciles its apps.
4. **Verify** — confirm infrastructure applied cleanly and applications are healthy
   (see the runbook).

---

## Runbook

### Part A — Cut the release (on `main`)
1. Identify the target Unique release; review its infrastructure-relevant changes (new or
   required environment variables and feature flags; dependency upgrades).
2. Branch from `main`: `chore/release-202X.XX`.
3. **Bump versions** in the affected app specs (`apps/*.yaml`: chart `targetRevision` + image tag).
4. **Update `defaults/`**: add newly-required flags / env defaults; leave optional ones out.
5. **Bump Terraform** module/provider versions in layers 01–05 if the release requires it.
6. Open a PR to `main`; CI must be green; review the per-layer plan.
7. Squash-merge; **tag `202X.XX.X`**; **publish the GitHub Release** with notes.

### Part B — Adopt a release in an environment (on `deploy`)
1. **Bring the release into the environment** — merge the release into the `deploy` branch so
   the environment's `apps/`, `defaults/`, and the layer 01–05 Terraform are at `202X.XX.X`.
   Supply any new instance values flagged with `unset_default_value` under
   `<env>/value-overlays/`. Commit.
2. **Push — this is the deployment:**
   - **Infrastructure:** the pipeline applies layers 01→05 for this environment. Watch to
     completion.
   - **Applications:** ArgoCD shows the environment's apps out of sync; review each diff
     (version bumps + new release config only), reconcile, and wait for **Healthy**.
3. Environments adopt independently — roll out to `sbx`, validate, then `prod`.

> **Note:** application versions are pinned **per environment** (in each env's app specs), so
> environments can run different app versions at once. The Terraform layer code is
> **shared** on the `deploy` branch — environments differ by *when each was last applied*, so
> advance and apply one environment at a time.

### Part C — Verify
- Infrastructure pipeline green for all five layers.
- ArgoCD apps **Synced + Healthy** for the environment.
- End to end: open a space, send a chat message, upload a document, ask a question that
  requires retrieval, and confirm a fresh sign-in works.

### Part D — Rollback
- **Applications:** re-point the environment to the previous release tag and reconcile, or
  roll the app back in ArgoCD. Schema migrations are forward-only — a version revert runs
  older code against a newer database schema, so prefer fixing forward for services that ran
  migrations.
- **Infrastructure:** revert the environment to the previous release and re-apply. Some
  changes are not reversible in place (for example, database engine version changes); plan
  data-tier rollbacks deliberately rather than via auto-apply.

---

## Consuming releases in your fork

Self-hosting means maintaining your **own private copy** of `hello-aws` (it carries your
`value-overlays/` — domains, identity, secret references) while tracking the public repo as
an **upstream** to pull releases from.

### Why not a GitHub "Fork"
A GitHub fork of a public repository is itself **public and cannot be made private**, so it is
unsuitable for a private deployment. Instead, create your own **private repository** and add
`hello-aws` as an `upstream` remote.

### Set up your private repository
Generic Git (works on any host):

```bash
# 1. Create an empty PRIVATE repo on your platform (see below), then mirror upstream into it:
git clone --bare https://github.com/Unique-AG/hello-aws.git
git -C hello-aws.git push --mirror <your-private-repo-url>

# 2. Clone your private repo and add the public upstream:
git clone <your-private-repo-url> && cd <your-repo>
git remote add upstream https://github.com/Unique-AG/hello-aws.git
git fetch upstream --tags
```

Creating the private repo, per platform. **Mirror-push** paths start from an empty repo and
use the recipe above; **Import** paths populate the repo on creation from the GitHub URL:
- **GitHub** (mirror-push) — create a new **private** repository, then mirror-push as above (a
  native *Fork* stays public).
- **Azure DevOps** (import) — *Repos → Import repository* with the GitHub URL, into a private
  project.
- **GitLab** (import) — *New project → Import project → Repository by URL*, or configure **pull
  mirroring** from the GitHub URL.
- **Bitbucket** (import) — *Import repository* with the GitHub URL.
- **AWS CodeCommit** (mirror-push) — create a repository, then mirror-push as above; pushing
  uses `git-remote-codecommit` or IAM-derived HTTPS Git credentials rather than a plain URL.

If you used an **Import** path (Azure DevOps / GitLab / Bitbucket), add the upstream remote
locally so you can pull releases (mirror-push users already did this in step 2):

```bash
git clone <your-private-repo-url> && cd <your-repo>
git remote add upstream https://github.com/Unique-AG/hello-aws.git
git fetch upstream --tags
```

### Adopt releases
1. **Watch the upstream GitHub Releases** to learn when a new version is available.
2. Keep your `main` free of local commits so it fast-forwards cleanly to each upstream release
   tag you adopt: `git fetch upstream --tags && git switch main && git merge --ff-only 202X.XX.X
   && git push`.
3. Maintain your `deploy` branch with one folder per environment, holding your real
   `value-overlays/`.
4. Adopt a release per environment with the
   **[Part B](#part-b--adopt-a-release-in-an-environment-on-deploy)** flow — `sbx` first, then
   `prod`.

Your `value-overlays/` is yours and persists across releases; adopting a tag advances only the
release content (versions + `defaults/`).

---

## Configuration reference (summary)

| You want to change… | Edit | Branch |
|---|---|---|
| Chart or image version (for a release) | `apps/<service>.yaml` | `main`, then tag |
| A release-wide default (flag, env wiring, default sizing) | `defaults/<service>.yaml` | `main` |
| Which release an environment runs | merge the release into `<env>/apps/` | `deploy` |
| Your domains / identity / registry / secrets | `<env>/value-overlays/` | `deploy` |
| Enable an optional feature for your install | `<env>/value-overlays/<service>` | `deploy` |
| Per-environment sizing (e.g. prod > sbx) | `<env>/value-overlays/<service>` | `deploy` |
