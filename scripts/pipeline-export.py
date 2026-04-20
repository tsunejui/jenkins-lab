#!/usr/bin/env python3
"""Export a pipeline's config, metadata, and last-build artefacts.

Usage: pipeline-export.py <NAME> [DIR]   (DIR defaults to ./exports)

Writes:
  <DIR>/<NAME>/config.xml
  <DIR>/<NAME>/info.json
  <DIR>/<NAME>/last-build.json
  <DIR>/<NAME>/stages.json
  <DIR>/<NAME>/console.log
"""
import base64
import json
import os
import sys
import urllib.request

BASE = os.environ["JENKINS_URL"]
AUTH = base64.b64encode(
    f"{os.environ['JENKINS_ADMIN_ID']}:{os.environ['JENKINS_ADMIN_PASSWORD']}".encode()
).decode()
HEADERS = {"Authorization": f"Basic {AUTH}"}


def fetch(path: str, as_bytes: bool = False):
    req = urllib.request.Request(f"{BASE}{path}", headers=HEADERS)
    raw = urllib.request.urlopen(req, timeout=15).read()
    return raw if as_bytes else json.loads(raw)


def save(outdir: str, name: str, data) -> None:
    path = os.path.join(outdir, name)
    if isinstance(data, (dict, list)):
        with open(path, "w") as f:
            json.dump(data, f, indent=2)
    elif isinstance(data, bytes):
        with open(path, "wb") as f:
            f.write(data)
    else:
        with open(path, "w") as f:
            f.write(data)
    print(f"  {path}  ({os.path.getsize(path)} bytes)")


def main(name: str, outroot: str) -> int:
    outdir = os.path.join(outroot, name)
    os.makedirs(outdir, exist_ok=True)
    print(f"Exporting '{name}' → {outdir}/")

    try:
        save(outdir, "config.xml", fetch(f"/job/{name}/config.xml", as_bytes=True))
    except Exception as exc:
        print(f"cannot fetch job '{name}': {exc}", file=sys.stderr)
        return 1

    job = fetch(f"/job/{name}/api/json")
    save(outdir, "info.json", job)

    lb = job.get("lastBuild")
    if not lb:
        print("  (no builds yet → skipping build/stage/console)")
        return 0
    num = lb["number"]

    save(outdir, "last-build.json", fetch(f"/job/{name}/{num}/api/json"))
    try:
        save(outdir, "stages.json", fetch(f"/job/{name}/{num}/wfapi/describe"))
    except Exception as exc:
        print(f"  stages.json skipped ({exc})")
    try:
        save(outdir, "console.log", fetch(f"/job/{name}/{num}/consoleText", as_bytes=True))
    except Exception as exc:
        print(f"  console.log skipped ({exc})")
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: pipeline-export.py <NAME> [DIR]", file=sys.stderr)
        sys.exit(2)
    name = sys.argv[1]
    outroot = sys.argv[2] if len(sys.argv) > 2 else "./exports"
    sys.exit(main(name, outroot))
