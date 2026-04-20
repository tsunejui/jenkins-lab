#!/usr/bin/env python3
"""Print a consolidated summary of a single Jenkins pipeline.

Usage: pipeline-info.py <NAME>
"""
import base64
import datetime
import json
import os
import sys
import urllib.request

BASE = os.environ["JENKINS_URL"]
AUTH = base64.b64encode(
    f"{os.environ['JENKINS_ADMIN_ID']}:{os.environ['JENKINS_ADMIN_PASSWORD']}".encode()
).decode()
HEADERS = {"Authorization": f"Basic {AUTH}"}


def get(path: str) -> dict:
    req = urllib.request.Request(f"{BASE}{path}", headers=HEADERS)
    return json.loads(urllib.request.urlopen(req, timeout=10).read())


def when(ms: int) -> str:
    return datetime.datetime.fromtimestamp(ms / 1000).isoformat(timespec="seconds")


def main(name: str) -> int:
    tree = (
        "name,_class,description,buildable,disabled,nextBuildNumber,url,color,"
        "lastBuild[number,result,duration,timestamp,url],"
        "builds[number,result,duration,timestamp]"
    )
    try:
        job = get(f"/job/{name}/api/json?tree={tree}")
    except Exception as exc:
        print(f"cannot fetch job '{name}': {exc}", file=sys.stderr)
        return 1

    print(f"Name          : {job['name']}")
    print(f"Class         : {job['_class'].rsplit('.', 1)[-1]}")
    print(f"URL           : {job['url']}")
    if job.get("description"):
        print(f"Description   : {job['description']}")
    print(f"Buildable     : {job.get('buildable')}")
    if job.get("disabled"):
        print("Disabled      : True")
    print(f"Next build #  : {job.get('nextBuildNumber')}")
    print(f"Color         : {job.get('color')}")

    lb = job.get("lastBuild")
    if not lb:
        print("\n(no builds yet)")
        return 0

    print(
        f"\nLast build    : #{lb['number']} "
        f"{lb.get('result') or 'RUNNING'}  "
        f"duration={lb['duration']}ms  at {when(lb['timestamp'])}"
    )
    print(f"                {lb['url']}")

    try:
        wf = get(f"/job/{name}/lastBuild/wfapi/describe")
        print("\nStages (last build):")
        for s in wf.get("stages", []):
            print(f"  {s['name']:<18} {s['status']:<10} {s['durationMillis']:>6}ms")
    except Exception as exc:
        print(f"\n(stage info unavailable: {exc})")

    builds = (job.get("builds") or [])[:8]
    if builds:
        print("\nRecent builds:")
        for b in builds:
            print(
                f"  #{b['number']:<4} {(b.get('result') or 'RUNNING'):<8} "
                f"{b['duration']:>6}ms  {when(b['timestamp'])}"
            )
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: pipeline-info.py <NAME>", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
