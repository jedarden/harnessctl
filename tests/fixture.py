#!/usr/bin/env python3
"""Create a signed release with a disposable test key; never use a live signer."""
import importlib.util
from pathlib import Path
import re
import shutil
import subprocess
import sys

source = Path(__file__).resolve().parent.parent
target = Path(sys.argv[1])
target.mkdir(parents=True)
(target / "scripts").mkdir()
(target / "keys").mkdir()
for name in ("start.sh", "scripts/install.sh.in", "scripts/release.py"):
    shutil.copy2(source / name, target / name)
private = target.parent / "test-signing.pem"
subprocess.run(["openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048",
                "-out", str(private)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
private.chmod(0o600)
public = subprocess.check_output(["openssl", "pkey", "-in", str(private), "-pubout"]).decode()
launcher = (target / "start.sh").read_text()
launcher = launcher.replace('ARTIFACT_TRUSTED_KEY_ID="bootstrap-rsa-2026-10"', 'ARTIFACT_TRUSTED_KEY_ID="fixture-test"')
launcher = re.sub(r"(?<=<<'ARTIFACT_KEY'\n).*?(?=\nARTIFACT_KEY)", public.strip(), launcher, flags=re.S)
(target / "start.sh").write_text(launcher)
(target / "keys/release-signing.pub").write_text(public)
spec = importlib.util.spec_from_file_location("release", source / "scripts/release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
release.generate(target)
(target / "artifact-manifest.txt").write_text(release.manifest(target))
release.sign(str(private), root=target)
