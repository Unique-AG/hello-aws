## What changed

<!-- The change and the reason for it, in a few lines. -->

## Checks

- [ ] Terraform changes: `./scripts/validate.sh <layer> <env> true` passes — format, tflint,
      shellcheck, trivy and checkov. CI runs `terraform validate` on top of this.
- [ ] No credentials, tenant names or environment-specific values are added — this repository is public

### Runbook
- [ ] No registered procedure (for example docs/release-concept.md) changes how it works
- [ ] A registered procedure changes, and its runbook changes in this pull request
- [ ] Approving code owner: runbook line checked before approval
