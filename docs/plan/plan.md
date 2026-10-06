# harnessctl implementation plan

Outcome owner: hstart-baef6ea7. Extract the existing launcher from bootstrap
into harnessctl without losing signed updates, resume behavior, or the fleet's
defaults.

Status: completed on 2026-10-03 with signed v1.4.0 and the bootstrap bridge.
This file is retained as a historical implementation record; current design and
operations live in [architecture](../architecture.md) and the
[release runbook](../operations/releasing.md).

The distribution unit is one Bash launcher. Configuration belongs to the user;
release metadata and the pinned public key belong to this repository. The
installer is generated from the launcher's trust anchor and verifier to prevent
drift. Python's standard library prepares and checks release artifacts; OpenSSL
verifies RSA/SHA-256 signatures. OpenBao Transit holds the shared, non-exportable
signing key. A protected Argo ContainerSet separates preparation, signing,
verification, and publishing. Forgejo is the writable origin and mirrors to
GitHub, whose raw endpoint distributes signed payloads.

Completed implementation phases:

1. Extract the launcher; add explicit updates, separate agent-update control,
   user configuration, a signed installer, and independent release tooling.
2. Verify offline signed fixtures, installation failures, argv behavior,
   configuration, source-checkout protection, and real tmux execution.
3. Deploy the protected release template through declarative-config, publish
   signed v1.4.0, and verify Forgejo/GitHub/raw convergence.
4. Publish a bootstrap transition through its protected signing flow. Its
   bridge keeps bootstrap's own REPO_URL and uses a separate launcher update
   URL, allowing future harness releases without bootstrap releases.
5. Install and verify the released launcher and record delivery evidence on
   the owning bead. Preserve concurrent checkout edits throughout.

Platform scope is Linux with Bash 4+ and GNU coreutils. macOS portability,
additional harnesses, new signing keys, and automatic release triggers are
future decisions rather than requirements for this extraction.
