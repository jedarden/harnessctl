# Security

## Permission policy

The default `START_SH_PERMISSION_MODE=bypass` is retained for compatibility
with the original launcher on dedicated, single-tenant hosts. It passes
Claude's dangerous permission-skip option or Codex's approval-and-sandbox
bypass option. This is unsuitable for an ordinary shared or personal machine.

Set the following before launching untrusted work:

```bash
START_SH_PERMISSION_MODE=default start codex
```

Persist the setting in `~/.config/harnessctl/config.sh` when bypass is not an
intentional host policy.

## Trust model

The installer and updater validate a signed manifest with a public key embedded
in the launcher. The manifest binds the release version and SHA-256 digest of
every installed artifact. Updates are downloaded to a same-filesystem temporary
file, authenticated, syntax-checked, made executable, and atomically renamed
over the deployed launcher. A failed step preserves the installed file.

This protects updates only after a trusted launcher or installer has been
obtained. Downloading an installer and its checksum from the same mutable or
compromised channel does not independently authenticate the bootstrap. The
README therefore pins the installer to an immutable Git commit and publishes a
checksum and public-key fingerprint suitable for comparison through another
trusted channel.

The current public-key DER SHA-256 fingerprint is:

```text
f8e3bdf686cbdcbf5608276b2e63db734f64e9329cfaac7c12843826aee14080
```

Production signatures use RSA/SHA-256 through a non-exportable OpenBao Transit
key. Only the signer container receives the projected OpenBao token. The
repository contains the public key, never private signing material.

## Key rotation

Rotation is a two-release transition:

1. Release a launcher that trusts both the old and new public keys, signed by
   the old key.
2. After deployed launchers have adopted the transition, sign manifests with
   the new key.
3. Remove the old key only in a later release after the migration window.

Changing the key identifier or public key without this overlap strands existing
installations.

## Reporting a vulnerability

Report security issues privately to the repository owner through Forgejo or an
established private contact. Do not include credentials, tokens, private keys,
or exploitable production details in a public issue. Include the affected
version, reproduction conditions, and whether the issue compromises bootstrap
trust, update verification, argument quoting, or permission isolation.
