#!/usr/bin/env python3
"""List WorkflowJob entries on the controller with status + URL."""
import base64
import json
import os
import sys
import urllib.request

BASE = os.environ["JENKINS_URL"]
AUTH = base64.b64encode(
    f"{os.environ['JENKINS_ADMIN_ID']}:{os.environ['JENKINS_ADMIN_PASSWORD']}".encode()
).decode()

STATUS = {
    "blue": "SUCCESS",
    "red": "FAILED",
    "yellow": "UNSTABLE",
    "aborted": "ABORTED",
    "disabled": "DISABLED",
    "notbuilt": "NEVER_RUN",
}


def main() -> int:
    url = f"{BASE}/api/json?tree=jobs[name,_class,color,url]"
    req = urllib.request.Request(url, headers={"Authorization": f"Basic {AUTH}"})
    try:
        data = json.loads(urllib.request.urlopen(req, timeout=10).read())
    except Exception as exc:
        print(f"query failed: {exc}", file=sys.stderr)
        return 1

    rows = [j for j in data.get("jobs", []) if j["_class"].endswith("WorkflowJob")]
    if not rows:
        print("(no pipeline jobs)")
        return 0

    nw = max(len(j["name"]) for j in rows)
    print(f"{'NAME':<{nw}}  {'STATUS':<18}  URL")
    print("-" * (nw + 2 + 18 + 2 + 40))
    for j in rows:
        color = j.get("color") or "notbuilt"
        running = color.endswith("_anime")
        base = color.replace("_anime", "")
        status = STATUS.get(base, base.upper())
        if running:
            status += " (running)"
        print(f"{j['name']:<{nw}}  {status:<18}  {j['url']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
