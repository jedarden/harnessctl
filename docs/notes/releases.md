# Release and bootstrap migration

`harnessctl-release-sign` lives at
`declarative-config/k8s/iad-ci/argo-workflows/harnessctl-release-sign-workflowtemplate.yml`.
Submit it by reference with an exact Forgejo main commit and a forward version:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: harnessctl-release-sign-manual-
  namespace: argo-workflows
spec:
  workflowTemplateRef:
    name: harnessctl-release-sign
  arguments:
    parameters:
      - name: expected-commit
        value: <40-hex Forgejo main commit>
      - name: version
        value: 1.4.0
```

The inherited `bootstrap-release-signer` service account is deliberately absent
from the Workflow submission. Its admission guard rejects direct use. Only the
sign container sees the projected OpenBao token. Source, public key, archive,
and manifest agree before the final changed-path allowlist and fast-forward push.
Verify the release commit on Forgejo and GitHub and compare raw artifact bytes
with the signed release before rolling it out.

Bootstrap's old `hosts/ex44/start.sh` URL is retained as a transition source.
`harnessctl-bootstrap-adopt` takes `expected-commit` (bootstrap main),
`launcher-commit` (the signed harness main), and `version` (next bootstrap
version). It verifies the harness release before copying its launcher and
prepares, signs, verifies, and pushes a normal bootstrap release. The embedded
bridge preserves bootstrap's REPO_URL while directing launcher checks to
harnessctl. Existing installations fetch the bridge with their existing
trust anchor and then self-update independently. Fresh bootstrap installations
receive the same bridge. No host-local source patch is required.

For local preparation, use a clean bootstrap checkout and a signed harness
checkout:

```bash
scripts/adopt-bootstrap.sh /path/to/clean/bootstrap NEXT_BOOTSTRAP_VERSION
```

This prepares unsigned artifacts for the protected signer. It refuses dirty
bootstrap checkouts and mismatched public keys. Never commit an unsigned set
as a release or overwrite an older immutable archive.
