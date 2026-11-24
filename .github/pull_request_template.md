## What changed

<!-- The change and the reason for it, in a few lines. -->

## Checks

- [ ] Terraform changes: `./scripts/validate.sh <layer> <env> true` passes, where `<layer>` is
      one of bootstrap, governance, infrastructure, data-and-ai, compute. It runs tflint,
      shellcheck, trivy and checkov only where each is installed and skips the rest, so CI
      remains the authority — it runs all of them plus `terraform validate`.
- [ ] No credentials, tenant names or environment-specific values are added — this repository is public

### Runbook
- [ ] No registered procedure (for example docs/release-concept.md) changes how it works
- [ ] A registered procedure changes, and its runbook changes in this pull request
- [ ] Approving code owner: runbook line checked before approval
