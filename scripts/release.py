#!/usr/bin/env python3
"""Generate, prepare, sign, and verify self-contained launcher releases."""
import argparse
import base64
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
ARTIFACTS = ("start.sh", "install.sh", "start.sh.version")


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def metadata(root=ROOT):
    source = (root / "start.sh").read_text()
    version = re.search(r'^START_SH_VERSION="(\d+\.\d+\.\d+)"$', source, re.M).group(1)
    key_id = re.search(r'^ARTIFACT_TRUSTED_KEY_ID="([\w.-]+)"$', source, re.M).group(1)
    key = source.split("<<'ARTIFACT_KEY'\n", 1)[1].split("\nARTIFACT_KEY", 1)[0] + "\n"
    return source, version, key_id, key


def installer(root=ROOT):
    source, version, _, _ = metadata(root)
    trust = source[source.index('START_SH_VERSION="'):source.index('\n# Only the user')]
    functions = source[source.index('verify_artifact_manifest() {'):source.index('# Self-update function')]
    template = (root / "scripts/install.sh.in").read_text()
    generated = template.replace("@TRUST_BLOCK@", trust).replace("@VERIFY_FUNCTIONS@", functions)
    return generated, version


def generate(root=ROOT):
    generated, version = installer(root)
    (root / "install.sh").write_text(generated)
    (root / "install.sh").chmod(0o755)
    (root / "start.sh.version").write_text(version + "\n")


def parity(root=ROOT):
    generated, version = installer(root)
    if (root / "install.sh").read_text() != generated:
        raise ValueError("install.sh is stale; run scripts/release.py generate")
    if (root / "start.sh.version").read_text() != version + "\n":
        raise ValueError("start.sh.version disagrees with launcher")
    if metadata(root)[3].strip() != (root / "keys/release-signing.pub").read_text().strip():
        raise ValueError("launcher and pinned public key disagree")
    for name in ("start.sh", "install.sh"):
        run("bash", "-n", str(root / name))


def manifest(root=ROOT):
    _, version, key_id, _ = metadata(root)
    lines = ["format=harness-start-artifacts-v1", f"key_id={key_id}", f"version={version}"]
    for name in ARTIFACTS:
        lines.append(f"artifact={name} {hashlib.sha256((root / name).read_bytes()).hexdigest()}")
    return "\n".join(lines) + "\n"


def prepare(version, root=ROOT):
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("version must be MAJOR.MINOR.PATCH")
    source, current, _, _ = metadata(root)
    if tuple(map(int, version.split('.'))) <= tuple(map(int, current.split('.'))):
        raise ValueError("release version must move forward")
    archive = root / "releases" / f"v{version}"
    if archive.exists():
        raise ValueError("immutable release already exists")
    (root / "start.sh").write_text(source.replace(f'START_SH_VERSION="{current}"', f'START_SH_VERSION="{version}"', 1))
    generate(root)
    parity(root)
    (root / "artifact-manifest.txt").write_text(manifest(root))
    (root / "artifact-manifest.sig").unlink(missing_ok=True)
    print(f"Prepared unsigned harness-start v{version}; sign before publishing")


def verify(root=ROOT):
    parity(root)
    if (root / "artifact-manifest.txt").read_text() != manifest(root):
        raise ValueError("manifest does not bind the exact release files")
    _, _, key_id, _ = metadata(root)
    lines = (root / "artifact-manifest.sig").read_text().splitlines()
    if len(lines) != 2 or lines[0] != f"key_id={key_id}" or not lines[1].startswith("signature="):
        raise ValueError("malformed detached signature")
    signature = base64.b64decode(lines[1][10:], validate=True)
    with tempfile.NamedTemporaryFile() as tmp:
        tmp.write(signature)
        tmp.flush()
        run("openssl", "dgst", "-sha256", "-verify", str(root / "keys/release-signing.pub"),
            "-signature", tmp.name, str(root / "artifact-manifest.txt"), stdout=subprocess.DEVNULL)


def sign(key=None, transit=None, root=ROOT):
    _, _, key_id, _ = metadata(root)
    if bool(key) == bool(transit):
        raise ValueError("provide exactly one of --key or --transit-key")
    content = (root / "artifact-manifest.txt").read_bytes()
    if key:
        signature = run("openssl", "dgst", "-sha256", "-sign", key, input=content, stdout=subprocess.PIPE).stdout
    else:
        if not re.fullmatch(r"[\w-]+/[\w.-]+", transit):
            raise ValueError("Transit key must be MOUNT/KEY")
        mount, name = transit.split('/')
        response = run("bao", "write", "-field=signature", f"{mount}/sign/{name}",
                       "input=-", "hash_algorithm=sha2-256", "signature_algorithm=pkcs1v15", "prehashed=false",
                       input=base64.b64encode(content), stdout=subprocess.PIPE).stdout.decode().strip()
        match = re.fullmatch(r"vault:v\d+:([A-Za-z0-9+/]+=*)", response)
        if not match:
            raise ValueError("malformed Transit signature")
        signature = base64.b64decode(match[1], validate=True)
    (root / "artifact-manifest.sig").write_text(f"key_id={key_id}\nsignature={base64.b64encode(signature).decode()}\n")
    verify(root)


def archive(root=ROOT):
    verify(root)
    version = metadata(root)[1]
    destination = root / "releases" / f"v{version}"
    if destination.exists():
        raise ValueError("immutable release already exists")
    destination.mkdir(parents=True)
    for name in (*ARTIFACTS, "artifact-manifest.txt", "artifact-manifest.sig"):
        shutil.copy2(root / name, destination / name)
    print(f"Archived signed harness-start v{version}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    for command in ("generate", "parity", "check", "archive"):
        sub.add_parser(command)
    sub.add_parser("prepare-unsigned").add_argument("version")
    signer = sub.add_parser("sign")
    signer.add_argument("--key")
    signer.add_argument("--transit-key")
    args = parser.parse_args()
    try:
        if args.command == "prepare-unsigned":
            prepare(args.version)
        elif args.command == "sign":
            sign(args.key, args.transit_key)
        else:
            {"generate": generate, "parity": parity, "check": verify, "archive": archive}[args.command]()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Error: {error}\n")


if __name__ == "__main__":
    main()
