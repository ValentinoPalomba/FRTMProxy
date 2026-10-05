"""Restore the pinned upstream runtime without installing anything into the system."""
import hashlib
import json
import platform
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request
from pathlib import Path

from verify_engine import verify


def main():
    resources = Path(__file__).resolve().parents[1] / "FRTMProxy" / "Resources"
    metadata = json.loads((resources / "mitmdump.metadata.json").read_text())
    destination = resources / "mitmproxy.app"
    if destination.exists():
        verify(resources, metadata)
        return
    if platform.machine() != metadata["architecture"]:
        raise SystemExit("This pinned runtime requires an arm64 macOS host.")
    with tempfile.TemporaryDirectory(prefix="frtm-engine-") as temporary:
        root = Path(temporary).resolve()
        archive = root / "engine.tar.gz"
        with urllib.request.urlopen(metadata["archiveURL"], timeout=60) as response, archive.open("wb") as output:
            shutil.copyfileobj(response, output)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != metadata["archiveSHA256"]:
            raise SystemExit("Upstream archive checksum mismatch; no runtime installed.")
        with tarfile.open(archive) as bundle:
            # Python shipped with macOS predates tarfile's data filter.
            for member in bundle.getmembers():
                path = root / member.name
                if not path.resolve().is_relative_to(root) or member.isdev() or member.isfifo():
                    raise SystemExit("Unsafe archive member")
                if member.issym() or member.islnk():
                    target = (path.parent if member.issym() else root) / member.linkname
                    if not target.resolve().is_relative_to(root):
                        raise SystemExit("Unsafe archive link")
            bundle.extractall(root)
        app = root / "mitmproxy.app"
        subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], check=True, timeout=30)
        verify(root, metadata)
        shutil.move(str(app), destination)
    print("Pinned engine installed locally; system configuration unchanged.")


if __name__ == "__main__":
    main()
