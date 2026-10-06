# Release operations

Production releases are prepared and signed by the protected
`harnessctl-release-sign` WorkflowTemplate in `iad-ci`. The signer uses the
non-exportable `bootstrap-signing/bootstrap-rsa-2026-10` OpenBao Transit key.
Never export private key material or sign a production manifest locally.

## Prerequisites

- The owning bead describes the user-visible outcome and verification.
- The checkout is clean on `main` and pushed only to Forgejo `origin`.
- `scripts/check.sh` passes from the exact commit being released.
- The chosen version is strictly greater than the current release and
  `releases/vVERSION/` does not exist.
- The WorkflowTemplate is `Synced` in ArgoCD and visible in `iad-ci`.

Record the exact 40-character Forgejo main commit:

```bash
git status --short --branch
scripts/check.sh
git rev-parse HEAD
```

## Submit

Creating a one-shot Argo Workflow by template reference is the documented
cluster-write exception. Do not modify the ArgoCD-managed WorkflowTemplate.

```bash
kubectl --kubeconfig=/home/coding/.kube/iad-ci.kubeconfig create -f - <<'EOF'
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
        value: <40-hex-forgejo-main-commit>
      - name: version
        value: <next-semver>
EOF
```

The workflow fences the source commit, prepares unsigned artifacts, runs the
complete gate, signs only the manifest in Transit, verifies and archives the
release, restricts changed paths, commits, and fast-forwards Forgejo `main`.

## Monitor

Use the credential-free read-only endpoint after submission:

```bash
kubectl --server=http://traefik-iad-ci:8001 \
  get workflows -n argo-workflows --sort-by=.metadata.creationTimestamp | tail -20
kubectl --server=http://traefik-iad-ci:8001 \
  get workflow <workflow-name> -n argo-workflows \
  -o jsonpath='{.status.phase} - {.status.message}'
```

Pods are garbage-collected promptly. Stream logs while the workflow is running
or use the retained Argo UI logs. On failure, inspect failed node messages; do
not manually publish a partially prepared artifact set.

## Tag the release commit

The protected workflow publishes the authenticated release commit but does not
create its Git tag. After recording the exact release commit, add an annotated
tag and push only that tag to Forgejo:

```bash
git tag -a v<VERSION> <RELEASE_COMMIT> -m "harnessctl v<VERSION>: <summary>"
git push origin refs/tags/v<VERSION>
```

Never infer `<RELEASE_COMMIT>` from a moving branch after unrelated commits
have landed. Confirm the commit subject is `release(harnessctl): v<VERSION>`
and that its signed archive passes the checks below before tagging it.

## Verify publication

After success:

1. Pull Forgejo `main` without rewriting local work and identify the generated
   release commit and annotated tag.
2. Run `python3 scripts/release.py check` in a clean checkout of that commit.
3. Confirm `releases/vVERSION/` contains exactly the five signed release files
   and matches the root artifacts byte-for-byte.
4. Confirm the Forgejo tag points at the release commit.
5. Wait for the server-side GitHub mirror, then compare the raw Forgejo/GitHub
   artifacts with the authenticated local files.
6. Install into a disposable directory, run `--version`, `doctor`, and
   `update`, then verify an existing installation adopts the new version.
7. Record the workflow, commit, tag, artifact verification, mirror convergence,
   and rollout evidence on the owning bead.

## Failure and rollback

The workflow does not publish before all preparation and signature checks pass.
If it fails before its final push, fix the cause on `main` and submit a new run
with the new exact commit. Never reuse a version whose immutable archive was
published.

Released clients refuse downgrades. Roll back behavior by reverting the source
change and releasing that code under a higher semantic version. Do not rewrite
the tag, force-push, or modify an existing `releases/vVERSION/` directory.

## Bootstrap bridge

The original bootstrap repository uses the separate protected
`harnessctl-bootstrap-adopt` flow. A bridge release keeps bootstrap's own
distribution URL while setting the launcher update URL to harnessctl. Local
preparation requires a clean bootstrap checkout and a signed harness checkout:

```bash
scripts/adopt-bootstrap.sh /path/to/clean/bootstrap NEXT_BOOTSTRAP_VERSION
```

The script only prepares unsigned artifacts for the protected signer and
refuses dirty checkouts or mismatched public keys.
