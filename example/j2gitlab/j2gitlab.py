#!/usr/bin/env python3
"""Convert a Jenkins Declarative Pipeline into an approximate GitLab CI/CD YAML.

Usage:   j2gitlab.py <NAME> [EXPORTS_DIR]   (EXPORTS_DIR defaults to ./exports)

Reads `<EXPORTS_DIR>/<NAME>/config.xml`, extracts the Groovy script, parses the
Declarative structure (stage / steps / sh / echo / withCredentials), and emits
a best-effort `.gitlab-ci.yml` on stdout.

Limitations (by design — this is a lab tool, not a production converter):
  - Only Declarative Pipelines. Scripted Pipelines are not parsed.
  - `agent`, `when`, `post`, `environment`, `parallel`, shared libraries,
    and most options/triggers are ignored.
  - Only `echo`, `sh`, and `withCredentials` steps are recognised.
  - `withCredentials` is flattened: inner steps become plain script lines
    and credentials get surfaced under a top-level `variables:` block
    (which the GitLab project must configure as CI/CD variables).
"""
from __future__ import annotations

import html
import os
import re
import sys
import textwrap
from typing import Any


def extract_script(xml_path: str) -> str:
    """Return the Groovy pipeline script from a Jenkins config.xml."""
    with open(xml_path, encoding="utf-8") as f:
        content = f.read()
    m = re.search(r"<script>(.*?)</script>", content, re.DOTALL)
    if not m:
        raise SystemExit(f"error: no <script> section found in {xml_path}")
    return html.unescape(m.group(1))


def matching_brace(s: str, pos: int) -> int:
    """Return the index of the `}` that matches the `{` at `pos`.

    Honours Groovy single/double/triple quoted strings so braces embedded in
    shell snippets don't throw off the counter.
    """
    assert s[pos] == "{", f"expected '{{' at position {pos}, got {s[pos]!r}"
    depth = 0
    in_str: str | None = None
    i = pos
    while i < len(s):
        if in_str:
            if len(in_str) == 3 and s[i:i + 3] == in_str:
                i += 3
                in_str = None
                continue
            if len(in_str) == 1 and s[i] == in_str:
                in_str = None
            elif s[i] == "\\":
                i += 2
                continue
        else:
            if s[i:i + 3] in ("'''", '"""'):
                in_str = s[i:i + 3]
                i += 3
                continue
            if s[i] in ("'", '"'):
                in_str = s[i]
            elif s[i] == "{":
                depth += 1
            elif s[i] == "}":
                depth -= 1
                if depth == 0:
                    return i
        i += 1
    raise ValueError(f"unmatched {{ at position {pos}")


def parse_stages(script: str) -> list[dict[str, Any]]:
    """Find every `stage('name') { ... }` block in the script and return its
    body text alongside the stage name."""
    stages: list[dict[str, Any]] = []
    pattern = re.compile(r"stage\s*\(\s*['\"]([^'\"]+)['\"]\s*\)\s*\{")
    pos = 0
    while True:
        m = pattern.search(script, pos)
        if not m:
            break
        brace = m.end() - 1
        end = matching_brace(script, brace)
        stages.append({"name": m.group(1), "body": script[brace + 1:end]})
        pos = end + 1
    return stages


def extract_steps_body(stage_body: str) -> str | None:
    """Return the body text of the `steps { ... }` block inside a stage, or
    None if the stage has no steps (e.g. a parallel outer stage)."""
    m = re.search(r"steps\s*\{", stage_body)
    if not m:
        return None
    brace = m.end() - 1
    end = matching_brace(stage_body, brace)
    return stage_body[brace + 1:end]


def parse_steps(body: str) -> list[dict[str, Any]]:
    """Parse a steps-body into a list of step dicts."""
    steps: list[dict[str, Any]] = []
    i = 0
    while i < len(body):
        # Skip whitespace + line comments
        while i < len(body) and body[i] in " \t\n":
            i += 1
        if i < len(body) and body[i:i + 2] == "//":
            nl = body.find("\n", i)
            i = len(body) if nl == -1 else nl + 1
            continue
        if i >= len(body):
            break

        m = re.match(r"echo\s+(['\"])(.*?)\1", body[i:], re.DOTALL)
        if m:
            steps.append({"kind": "echo", "content": m.group(2)})
            i += m.end()
            continue

        m = re.match(r"sh\s+('''|\"\"\")([\s\S]*?)\1", body[i:])
        if m:
            raw = m.group(2).strip("\n")
            steps.append({"kind": "sh_block", "content": textwrap.dedent(raw)})
            i += m.end()
            continue

        m = re.match(r"sh\s+(['\"])(.*?)\1", body[i:], re.DOTALL)
        if m:
            steps.append({"kind": "sh", "content": m.group(2)})
            i += m.end()
            continue

        m = re.match(r"withCredentials\s*\(\s*\[([\s\S]*?)\]\s*\)\s*\{", body[i:])
        if m:
            creds = parse_credentials(m.group(1))
            brace = i + m.end() - 1
            end = matching_brace(body, brace)
            inner = parse_steps(body[brace + 1:end])
            steps.append({"kind": "withCreds", "creds": creds, "steps": inner})
            i = end + 1
            continue

        # Unknown construct — skip the rest of the line and keep going.
        nl = body.find("\n", i)
        i = len(body) if nl == -1 else nl + 1
    return steps


def parse_credentials(args: str) -> list[dict[str, str]]:
    """Parse the list inside withCredentials([...]). Handles string() and
    usernamePassword() entries — enough for the demo pipelines."""
    out: list[dict[str, str]] = []
    for m in re.finditer(r"(\w+)\s*\(([^)]+)\)", args):
        kind = m.group(1)
        params = dict(re.findall(r"(\w+)\s*:\s*['\"]([^'\"]+)['\"]", m.group(2)))
        out.append({"kind": kind, **params})
    return out


def emit_yaml(name: str, stages: list[dict[str, Any]]) -> str:
    lines: list[str] = []
    lines.append(f"# Auto-generated from Jenkins pipeline '{name}' by j2gitlab.py.")
    lines.append("# Review and edit before committing — mapping is best-effort.")
    lines.append("#")
    lines.append("# ─── test this file locally ────────────────────────────────────────────")
    lines.append("#   # via the shared harness (recommended)")
    lines.append("#   just test-gitlab")
    lines.append("#")
    lines.append("#   # manual run — copy to a temp dir first (gitlab-ci-local reads CWD)")
    lines.append(f"#   tmp=$(mktemp -d) && cp example/j2gitlab/samples/{name}.gitlab-ci.yml \"$tmp/.gitlab-ci.yml\"")
    lines.append(f"#   [ -f test/fixtures/{name}.variables.yml ] && \\")
    lines.append(f"#       cp test/fixtures/{name}.variables.yml \"$tmp/.gitlab-ci-local-variables.yml\"")
    lines.append('#   rel=$(python3 -c "import os;print(os.path.relpath(\'$tmp\'))")')
    lines.append("#   mise exec npm:gitlab-ci-local -- gitlab-ci-local --cwd \"$rel\" --list")
    lines.append("#   mise exec npm:gitlab-ci-local -- gitlab-ci-local --cwd \"$rel\" --preview")
    lines.append("#   mise exec npm:gitlab-ci-local -- gitlab-ci-local --cwd \"$rel\"")
    lines.append("# ───────────────────────────────────────────────────────────────────────")
    lines.append("")

    # Collect credentials referenced anywhere.
    cred_vars: list[tuple[str, str]] = []  # (varname, source cred id)
    seen: set[str] = set()

    def walk(steps_list: list[dict[str, Any]]) -> None:
        for st in steps_list:
            if st["kind"] == "withCreds":
                for c in st["creds"]:
                    if c["kind"] == "string" and "variable" in c:
                        if c["variable"] not in seen:
                            cred_vars.append((c["variable"], c.get("credentialsId", "?")))
                            seen.add(c["variable"])
                    elif c["kind"] == "usernamePassword":
                        for key in ("usernameVariable", "passwordVariable"):
                            if key in c and c[key] not in seen:
                                cred_vars.append((c[key], c.get("credentialsId", "?")))
                                seen.add(c[key])
                walk(st["steps"])

    for st in stages:
        walk(st["steps"])

    if cred_vars:
        lines.append("# Configure these as protected CI/CD variables in GitLab:")
        lines.append("#   Settings → CI/CD → Variables")
        lines.append("variables:")
        for var, cred_id in cred_vars:
            lines.append(f"  {var}: \"${{{var}}}\"   # was Jenkins credentialsId '{cred_id}'")
        lines.append("")

    lines.append("stages:")
    for st in stages:
        lines.append(f"  - {yaml_scalar(st['name'])}")
    lines.append("")

    for st in stages:
        lines.append(f"{yaml_scalar(st['name'])}:")
        lines.append(f"  stage: {yaml_scalar(st['name'])}")
        lines.append("  script:")
        emit_scripts(st["steps"], lines, indent="    ")
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def emit_scripts(steps: list[dict[str, Any]], lines: list[str], indent: str) -> None:
    for st in steps:
        if st["kind"] == "echo":
            # Build the shell command, then YAML-quote the whole line so that
            # any '#' / ':' in the message doesn't get eaten by YAML parsing.
            line = f"echo {shell_single_quote(st['content'])}"
            lines.append(f"{indent}- {yaml_inline(line)}")
        elif st["kind"] == "sh":
            lines.append(f"{indent}- {yaml_inline(st['content'])}")
        elif st["kind"] == "sh_block":
            lines.append(f"{indent}- |")
            for sub in st["content"].split("\n"):
                lines.append(f"{indent}  {sub}")
        elif st["kind"] == "withCreds":
            emit_scripts(st["steps"], lines, indent)


# ─── small YAML / shell helpers ──────────────────────────────────────────────
YAML_SAFE = re.compile(r"^[A-Za-z_][A-Za-z0-9_\-]*$")


def yaml_scalar(s: str) -> str:
    return s if YAML_SAFE.match(s) else f'"{s}"'


def yaml_inline(s: str) -> str:
    if "\n" in s:
        return "|-\n    " + s.replace("\n", "\n    ")
    if re.search(r"[:#\[\]{},&*!|>%@`]", s) or s.startswith("-"):
        return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'
    return s


def shell_single_quote(s: str) -> str:
    if "'" not in s:
        return f"'{s}'"
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


# ─── entrypoint ──────────────────────────────────────────────────────────────
def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: j2gitlab.py <NAME> [EXPORTS_DIR]", file=sys.stderr)
        return 2
    name = argv[1]
    base = argv[2] if len(argv) > 2 else "./exports"
    xml = os.path.join(base, name, "config.xml")
    if not os.path.isfile(xml):
        print(f"error: {xml} not found — run `just pipeline-export {name}` first",
              file=sys.stderr)
        return 1
    script = extract_script(xml)
    stages = parse_stages(script)
    if not stages:
        print(f"error: no Declarative stages found in {xml}", file=sys.stderr)
        return 1
    for st in stages:
        body = extract_steps_body(st["body"])
        st["steps"] = parse_steps(body) if body else []
    sys.stdout.write(emit_yaml(name, stages))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
