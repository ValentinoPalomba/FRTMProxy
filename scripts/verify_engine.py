"""Verify every byte and symlink in the pinned embedded runtime, without executing it."""
import hashlib
import json
from pathlib import Path


def tree_digest(root):
    digest = hashlib.sha256()
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root).as_posix()
        if path.is_symlink():
            record = [relative, "link", str(path.readlink())]
        elif path.is_file():
            record = [relative, "file", hashlib.sha256(path.read_bytes()).hexdigest(), path.stat().st_mode & 0o777]
        else:
            continue
        digest.update(json.dumps(record, separators=(",", ":")).encode() + b"\n")
    return digest.hexdigest()


def verify(resources, metadata):
    binary = resources / metadata["filename"]
    if hashlib.sha256(binary.read_bytes()).hexdigest() != metadata["sha256"]:
        raise SystemExit("Embedded executable checksum mismatch.")
    if tree_digest(resources / "mitmproxy.app") != metadata["bundleSHA256"]:
        raise SystemExit("Embedded runtime checksum mismatch; restore the pinned upstream bundle.")


def main():
    resources = Path(__file__).resolve().parents[1] / "FRTMProxy" / "Resources"
    metadata = json.loads((resources / "mitmdump.metadata.json").read_text())
    verify(resources, metadata)
    print(f"Embedded runtime verified: mitmproxy {metadata['mitmproxyVersion']} ({metadata['architecture']})")


if __name__ == "__main__":
    main()
