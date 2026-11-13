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
| **Per-environment version** | per-environment **chart/image versions** (each env's `apps/` folder) enable staged rollout (`sbx` → validate → `prod`); `defaults/` is shared across environments |
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

**Per-layer checks** — run for each Terraform layer by CI
(`.github/workflows/tf.validate.yaml`); `scripts/validate.sh <layer> <env>` runs the same
checks locally:
- **Format** — `terraform fmt -check`
- **Validate** — `terraform init -backend=false` + `terraform validate`
- **Lint** — `tflint`
- **Security / IaC policy scanning** — `trivy` scans each layer's Terraform for
  misconfigurations and **fails the build on HIGH/CRITICAL**; `checkov` (3.x) runs the full
  Terraform policy set. Both are pinned, and trivy's check bundle is pinned by digest
  separately from its binary. Suppressions are `.trivyignore.yaml` entries for trivy and
  inline `#checkov:skip=` comments for checkov; every one is documented with rationale in
  [`docs/security-baseline.md`](security-baseline.md) — the single source of truth for
  suppressions and sbx relaxations, reviewed toward a goal of zero. Both scanners read the same
  three variable files: the tracked `common.auto.tfvars.template`, the environment's config, and
  `<layer>/terraform/environments/scan.tfvars` last. That last file defines the posture the gate
  checks — **every optional component switched on, every safety knob at its production value** —
  so neither a component an environment leaves off nor a relaxation it makes on purpose can
  escape the gate. A `count = 0` resource is not evaluated at all, which is why this matters.
- **Plan preview** — `terraform plan` posted as a PR comment (no apply on PRs)

**Repository-wide checks:**
- **Secret scanning** — push protection / pre-commit secret detection to keep credentials out
  of history
- **GitHub Advanced Security** — code scanning (CodeQL), dependency review, and Dependabot
  updates

These gates cover **this repository's IaC**. The **Unique application artifacts** a release
pins (container images and Helm charts) are independently built, scanned, and hardened through
Unique's **secure SDLC**: every build artifact is scanned for OS and dependency
vulnerabilities (Trivy), source is scanned (CodeQL), dependencies are auto-patched
(Renovate/Dependabot), and images are rebuilt weekly for base-image patches, with CVSS-based
remediation SLAs. See
[Vulnerability & Patch Management](https://docs.unique.ai/security-and-compliance/it-security/vulnerability-patch-management-process).

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
`value-overlays/` stay as they are.

**Scope of per-environment independence.** Chart and image versions are per environment (each
env's `apps/` folder), so environments can be **staged independently** on different versions.
`defaults/` (release config), by contrast, is **shared** across environments — once a release's
`defaults/` are on the `deploy` branch they apply to every environment. A staged rollout
therefore assumes a release's `defaults/` changes are backward-compatible with the previous
release (typically additive — new flags an older app version simply ignores). A **breaking**
`defaults/` change can't be staggered: roll it out to all environments together, or hold the
rollout until every environment can move.

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
  published as a **GitHub Release**. It corresponds to a Unique platform release — see the
  [Unique Release Notes & Calendar](https://docs.unique.ai/it-operators/installing-and-upgrading-unique/release-notes-and-calendar)
  for what each version changes, dependency upgrades, and any newly-required configuration.
- **Two dimensions.** A version names the Unique release it deploys *and* the revision of this
  deployment:
  - `202X.XX.X` — deploys that Unique release.
  - `202X.XX.X-aws.N` — the **same** Unique release, next revision of the deployment. Cut this
    when a fix changes only this repository (an egress policy, a Terraform or proxy setting, a
    test) and moves no Unique component; the component table against the previous release is
    then empty, which is correct. Without this dimension a deployment fix cannot be released at
    all until Unique publishes a new version.
  - The publish guard compares the app-spec pins against the part **before** `-aws.`, so an
    `-aws` revision touches no app spec.

  List these tags with `git tag --sort=version:refname` — the default listing is lexical, so
  `-aws.10` would sort before `-aws.2`. Do not feed them to a semver precedence comparator:
  `-aws.N` sits in the pre-release slot while meaning the opposite.
- **GitHub Release.** The GitHub Release wraps the tag with human-facing notes — what changed,
  dependency upgrades, and any newly-required configuration — and is what consumers **watch**
  to learn a new version is available.
- **Component versions** (per-service chart version and image tag) live in the **app specs**
  under `06-applications/sbx/apps/`. Diff the versions between two releases:
  `git diff 202X.21.0 202X.22.0 -- 06-applications/sbx/apps`.
- **Per-environment version.** An environment's **chart/image versions** are the content of its
  `<env>/apps/` folder on `deploy`, advanced by merging a release — so environments can be
  staged on different versions. `defaults/` (release config) is **shared** across environments,
  not per-environment (see [How they compose](#how-they-compose)).
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
  Application per service from that environment's folder, resolving values from the env folder
  on `deploy` (see [How they compose](#how-they-compose)).
- Applications are reconciled when the environment's folder on `deploy` advances.
- **Bootstrapping ArgoCD** is handled by the deploy workflow: after the cluster exists (the
  compute layer, Track 1), a job installs ArgoCD and the ApplicationSets via
  `helmfile -e <env> -f 06-applications/argo-bootstrap.yaml.gotmpl sync`, run on a VPC runner
  with cluster access. From then on, app changes reconcile automatically.

---

## How a release flows

1. **Prepare on `main`** — bump the chart + image versions in the affected app specs
   (`apps/*.yaml`) and update `defaults/` for any new or newly-required release config, and the
   Terraform module/provider versions for the release. Open a PR; CI gates it; squash-merge.
   **No tag yet.**
2. **Adopt for validation** — bring that merge commit into `deploy` for **`sbx`** (the
   validation environment; in a fork, whichever environment you stage on) and supply any new
   instance values in `<env>/value-overlays/`, then push (see
   [Part B](#part-b--adopt-a-release-in-an-environment-on-deploy)). The Terraform pipeline
   applies that environment's infrastructure; ArgoCD reconciles its apps.
3. **Validate** — infrastructure applied cleanly, applications healthy, and the end-to-end
   suites pass against that environment.
4. **Publish** — tag the validated commit `202X.XX.X`. The release workflow refuses to publish
   unless that commit was validated and the environment has not moved since. **This is the
   release.**
5. **Adopt elsewhere** — further environments adopt the published release.

A release is published only after it has run somewhere. The tag of a published release cannot
be moved, so this ordering is the last point at which a mistake is still cheap. Re-running the
release workflow for an existing tag regenerates its notes, but never changes the commit it
names.

---

## Runbook

### Part A — Cut the release (on `main`)
1. Identify the target Unique release; review its infrastructure-relevant changes (new or
   required environment variables and feature flags; dependency upgrades).
2. Branch from `main`: `chore/release-202X.XX`.
3. **Bump versions** in the affected app specs (`apps/*.yaml`: chart `targetRevision` + image tag).
4. **Update `defaults/`**: add newly-required flags / env defaults. Optional ones belong here
   only when the fleet should adopt them together — list each in the release's upgrade notes
   with its effect, since `defaults/` is shared and every environment inherits it on adoption.
5. **Bump Terraform** module/provider versions in layers 01–05 if the release requires it.
6. If the release needs operator action (new instance values, renamed flags, manual steps),
   add it to the PR as `docs/releases/202X.XX.X.md`; it heads the release notes.
7. Open a PR to `main`; CI must be green; review the per-layer plan.
8. Squash-merge. **Do not tag yet** — the tag is cut in Part D, once the release has run in an
   environment.

### Part B — Adopt a release in an environment (on `deploy`)
1. **Bring the release into the environment** — merge it into the `deploy` branch so the
   environment's `apps/`, `defaults/`, and the layer 01–05 Terraform are at `202X.XX.X`. For the
   validation environment — **`sbx`** — this is the Part A merge commit, which is not yet
   tagged; for every other environment it is a published release.
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
- The end-to-end suites pass against this environment. On **`sbx`** this is the evidence
  Part D gates on, so run them at the commit you intend to tag.

### Part D — Publish the release
1. **Tag the validated commit.** Push the tag
   (`git tag -a 202X.XX.X -m 202X.XX.X <validated-sha> && git push origin 202X.XX.X`), which
   names that commit explicitly. Dispatching the **`[rel] Release`** workflow instead tags the
   **tip of `main`** — the same thing only while the tip is still the commit you validated, so
   check that before using it. That caveat applies only when the tag does not yet exist: once
   it does, a dispatch republishes the commit the tag names, so retrying a failed publish is
   safe.
2. The workflow (`.github/workflows/release.yaml`) refuses to publish unless **all** hold:
   - the target commit is on `main`;
   - the app specs at that commit pin the version — the part before `-aws.` for a revision.
     The pin check compares values **shaped like a release version**: a chart pinned to its own
     semver is ignored by design, but so is a pin like `latest`, which passes unexamined;
   - the smoke suite has a successful run **at that commit** whose published evidence shows
     **no failures, nothing flaky, nothing skipped, and at least one test run**;
   - that run validated the **current** `deploy/sbx`, and the deploy branch did not move during
     the run. A later push invalidates the evidence and the suite must run again;
   - the `deploy/sbx` revision it validated **pins this version too** — otherwise the suite
     passed against a cluster that is not running the release. The deploy branch advances by
     cherry-pick, so the release commit is never its ancestor and the two revisions cannot be
     compared directly; what they pin can be.

   This applies to an `-aws.N` revision exactly as to a version bump. A deployment-only fix is
   not inherently safer: configuration is where breakage tends to come from, and the suites
   take minutes.

   Nothing flaky counts as passing. A test that failed and succeeded on retry is a turn that
   failed against the release, and the run conclusion alone will not show it.
4. It then **publishes the GitHub Release** titled `Release 202X.XX.X`: a link to that Unique
   release's notes on docs.unique.ai, the upgrade notes from `docs/releases/<tag>.md`, a
   component version table diffed against the previous release (`scripts/release-notes.sh`),
   and the merged pull requests.

A refusal here is the gate working. Validate the commit, or do not publish it.

### Part E — Rollback
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
