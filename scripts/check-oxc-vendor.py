#!/usr/bin/env python3
"""Verify vendor provenance, exact patch reconstruction and preserved license."""
import hashlib
import json
import pathlib
import shutil
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def validate(root=ROOT):
    vendor = root / "vendor/oxc_parser"
    meta = json.loads((vendor / "UPSTREAM.json").read_text())
    manifest = (vendor / "UPSTREAM.manifest.sha256").read_text()
    require(hashlib.sha256((vendor/"stack-budget.patch").read_bytes()).hexdigest() == meta["patchSHA256"], "Recorded patch changed")
    require(meta["version"] == "0.152.0", "Unexpected vendor version")
    require(hashlib.sha256(manifest.encode()).hexdigest() == meta["unmodifiedSourceManifestSHA256"], "Upstream manifest changed")
    originals = {}
    for line in manifest.splitlines():
        digest, path = line.split("  ", 1)
        relative = pathlib.PurePosixPath(path)
        require(not relative.is_absolute() and ".." not in relative.parts and path not in originals,
                "Invalid upstream manifest path")
        originals[path] = digest
    require(len(originals) == 53, "Published source inventory is incomplete")
    modified = set(meta["modifiedUpstreamFiles"])
    require(modified == {"src/lib.rs", "src/cursor.rs", "src/js/expression.rs"}, "Unexpected upstream modifications")
    for name, digest in originals.items():
        require((vendor/name).is_file(), "Missing vendored upstream file: " + name)
        if name not in modified:
            require(hashlib.sha256((vendor/name).read_bytes()).hexdigest() == digest, "Modified upstream file: " + name)
    with tempfile.TemporaryDirectory() as temporary:
        destination = pathlib.Path(temporary)
        for name in modified:
            path = destination/name;path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(vendor/name, path)
        result = subprocess.run(["rtk", "proxy", "patch", "--batch", "--reverse", "--strip=1", "--directory", temporary,
                                 "--input", str(vendor/"stack-budget.patch")], capture_output=True, text=True, timeout=30)
        require(result.returncode == 0, "Recorded vendor patch cannot be reversed")
        for name in modified:
            require(hashlib.sha256((destination/name).read_bytes()).hexdigest() == originals[name], "Vendor patch does not reconstruct original: " + name)
    require(hashlib.sha256((vendor/"LICENSE").read_bytes()).hexdigest() == meta["licenseSHA256"], "Upstream license changed")
    actual = {str(p.relative_to(vendor)) for p in vendor.rglob("*") if p.is_file()}
    require(actual == set(originals) | {"LICENSE", "UPSTREAM.json", "UPSTREAM.manifest.sha256", "stack-budget.patch", "PATCH-NOTES.md"}, "Unexpected vendored files")
    return {"upstreamFiles":len(originals), "modifiedFiles":sorted(modified), "passed":True}


if __name__ == "__main__":
    print("OXC_VENDOR_OK " + json.dumps(validate()))
