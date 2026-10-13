# Release signing key rotation

The release signer is the non-exportable OpenBao Transit key
`bootstrap-signing/bootstrap-rsa-2026-10`. Its public key is pinned in
`keys/release-signing.pub` and embedded in `start.sh`; the generated
`install.sh` copies the launcher's trust block. Rotate by creating a **new
named Transit key**, publishing a release that trusts both keys while the old
key still signs, and only then switching the signer. Rotating versions of the
same Transit key name would leave old launchers unable to distinguish the
public keys by manifest `key_id`.

Use one owning bead for the rotation and record both release commits, workflow
runs, mirror checks, and representative client checks. Follow
[releasing.md](releasing.md) for the protected signing workflow, tagging, and
publication checks. Plan an overlap window long enough for installed launchers
and bootstrap bridges to receive the transition release. Clients that still
trust only the old key cannot update from a new-key-signed release; arrange a
fresh install or other authenticated recovery for clients that miss the window.

## Prepare the new key

1. Freeze unrelated release pushes during the signer switch. Identify the
   OpenBao instance that owns `bootstrap-signing`, and create a new
   non-exportable RSA-3072 Transit key with a distinct ID, for example
   `bootstrap-rsa-YYYY-MM`. Retain the old key throughout the overlap and
   rollback window. The release workflow signs with RSA/SHA-256 PKCS#1 v1.5.
2. Read the **public** PEM from the new Transit key metadata into a temporary
   file in this checkout, then validate its syntax and fingerprint. Do not
   export private key material or sign production artifacts locally. For an
   already-created key, with `bao` pointed at the owning instance:

   ```bash
   NEW_KEY_ID=bootstrap-rsa-YYYY-MM
   bao read -format=json "bootstrap-signing/keys/$NEW_KEY_ID" |
     jq -r '.data.keys[.data.latest_version | tostring].public_key' > keys/release-signing.next.pub
   openssl pkey -pubin -in keys/release-signing.next.pub -noout
   openssl pkey -pubin -in keys/release-signing.next.pub -outform DER |
     sha256sum
   ```

   Check the returned key name, type, and latest version in Transit metadata;
   record the public-key fingerprint on the bead. Keep the temporary
   public-key file out of commits; remove it after the switch.

## Publish the overlap release with the old signer

1. In `start.sh`, leave `ARTIFACT_TRUSTED_KEY_ID`, its PEM, and
   `keys/release-signing.pub` set to the **old** key. After the existing
   `ARTIFACT_TRUSTED_KEY_IDS` and `ARTIFACT_TRUSTED_PUBLIC_KEYS` initializers,
   embed the new PEM in a second here-document and append its ID and PEM to
   the two arrays in the same order. The manifest still names the old key.
   The arrays are used by both the launcher and installer verifier.
2. Run `python3 scripts/release.py generate` to copy the new trust block into
   `install.sh` and refresh `start.sh.version`. `generate` does **not** edit
   `start.sh` or `keys/release-signing.pub`. Run `scripts/check.sh`, inspect the
   trust block in both launchers, commit the source and generated installer,
   and push `main` to Forgejo. Let the protected workflow publish an immutable
   release signed by the old key.
3. Complete the publication checks in [releasing.md](releasing.md). Verify a
   previously installed old-only launcher updates to the dual-anchor release.
   The offline overlap fixture in `tests/install-update-test.sh` verifies both
   signature paths. Confirm the GitHub mirror has the transition release
   before changing the signer. Keep the old signer active while reachable
   old-only clients update; record remaining offline clients and their
   recovery plan.

## Switch signing to the new key

1. Update the protected `harnessctl-release-sign` WorkflowTemplate's Transit
   key reference in `declarative-config` through GitOps, then wait for ArgoCD
   to report it `Synced`. Do not patch the live WorkflowTemplate. Keep other
   release pushes frozen between this change and the matching source push.
2. In `start.sh`, set `ARTIFACT_TRUSTED_KEY_ID` and its PEM to the new key. Keep
   the old ID and PEM as the second entries in the trusted arrays. Copy
   `keys/release-signing.next.pub` to `keys/release-signing.pub`. The primary
   ID and PEM must match the protected signer because `scripts/release.py`
   uses them for manifest generation and local verification.
3. Run `python3 scripts/release.py generate` and `scripts/check.sh`, then
   commit and push the matching source to Forgejo `main`. The release sensor
   must submit this exact commit to the now-new-key signer. Verify the
   resulting immutable release, Forgejo and GitHub convergence, and update
   from a dual-anchor installation. Confirm its manifest and detached
   signature name the new key. Record the workflow and release commit.
4. Retain both trusted anchors while either signer may be needed. Remove the
   old anchor only in a later, forward release after installed clients and
   bootstrap bridges have migrated and the old key is no longer a recovery
   path. Never delete or disable the old Transit key during the overlap.

## Bootstrap bridge

`scripts/adopt-bootstrap.sh` copies harnessctl's launcher trust block into
bootstrap's `hosts/ex44/start.sh`, while preserving bootstrap's distribution
URL and directing launcher updates to harnessctl. It refuses to prepare a
bridge unless harnessctl's `keys/release-signing.pub` equals bootstrap's
`hosts/ex44/keys/bootstrap-artifacts-signing.pub`.

Prepare and publish a bootstrap bridge **during the old-signer overlap**, while
those pinned keys still match. Its copied launcher then trusts both old and
new harnessctl releases. After harnessctl switches its pinned key, bridge
preparation will refuse an old-pinned bootstrap checkout. Coordinate a
separate, authenticated bootstrap key transition before preparing another
bridge; do not bypass the equality check or merely copy a new public key into
bootstrap without its protected signer and signed release moving together.

## Failure and rollback

If the new-key workflow fails before publishing, keep the last verified
old-key release available. Correct the GitOps signer or source mismatch and
resubmit the exact source commit through the protected workflow. A release
already published under the new key is immutable. To restore earlier behavior
or return to the old signer, keep both anchors trusted, change the protected
signer and the source's primary key together, and publish the desired code
under a **higher semantic version**. Verify that release through the normal
publication checks. Never rewrite an existing archive or tag, force-push, or
ask clients to downgrade.
