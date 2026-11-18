#!/usr/bin/env python3
"""Check that no secret declared optional is wired through an ExternalSecret.

`06-applications/secrets.yaml` marks some secrets `optional: true`: the seeder
skips them when no source is configured and carries on. An ExternalSecret makes
no such allowance. It demands the value, fails to sync without it, and never
creates its target — so every workload mounting that target is stuck, whatever
the declaration said.

AlertManager sat in `Init:0/1` for six days that way, and nothing reported it,
because the component that raises alerts was the one that was down.

So the two sides have to agree: a secret is either required, or it is not read
through External Secrets Operator.

Run from the repository root:  python3 scripts/check-secret-optionality.py
Exit 0 = the declarations agree, exit 1 = a mismatch, naming both sides.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "06-applications" / "secrets.yaml"
SEARCH_ROOT = ROOT / "06-applications"

# `- { name: x, id: y, kind: external, ..., optional: true }` — one flow-style
# mapping per line, which is how the manifest is written throughout.
ENTRY = re.compile(r"^\s*-\s*\{(?P<body>.*)\}\s*$")
FIELD = re.compile(r"(?P<key>[A-Za-z_][\w-]*)\s*:\s*(?P<value>[^,}]+)")

# ESO addresses the store through `remoteRef` or `dataFrom[].extract`. Either may
# be quoted, open a sequence item, or be written as a block or a flow mapping;
# a form this misses is a conflict reported as clean.
KIND = re.compile(r"\bkind\s*:\s*[\"']?ExternalSecret[\"']?")
REF_BLOCK = re.compile(r"^(?P<indent>\s*)(?:-\s*)?(?:remoteRef|extract):\s*$")
REF_INLINE = re.compile(
    r"^\s*(?:-\s*)?(?:remoteRef|extract):\s*\{.*?\bkey\s*:\s*(?P<key>[^,}\s]+)"
)
KEY_LINE = re.compile(r"^\s*key:\s*(?P<key>.+?)\s*$")


def strip_comment(line: str) -> str:
    """Drop a YAML comment: a '#' outside quotes, at line start or after space.

    Without this a trailing comment is read as content, the pattern stops
    matching, and the check passes while the conflict is still there.
    """
    quote = None
    for i, ch in enumerate(line):
        if quote is not None:
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
        elif ch == "#" and (i == 0 or line[i - 1] in " \t"):
            return line[:i]
    return line


def unquote(value: str) -> str:
    return value.strip().strip('"').strip("'")


def optional_secret_ids() -> dict[str, int]:
    """Secret ids declared optional, mapped to their line number."""
    found: dict[str, int] = {}
    for lineno, line in enumerate(MANIFEST.read_text(encoding="utf-8").splitlines(), 1):
        entry = ENTRY.match(strip_comment(line))
        if not entry:
            continue
        fields = {m["key"]: unquote(m["value"]) for m in FIELD.finditer(entry["body"])}
        if fields.get("optional") != "true":
            continue
        # remoteRef.key addresses the store, which is `id` when it differs from
        # the logical name.
        found[fields.get("id") or fields["name"]] = lineno
    return found


def external_secret_refs() -> list[tuple[str, Path, int]]:
    """Every (key, file, line) an ExternalSecret reads from the store."""
    refs: list[tuple[str, Path, int]] = []
    for path in sorted(SEARCH_ROOT.rglob("*.yaml")):
        text = path.read_text(encoding="utf-8")
        if not KIND.search(text):
            continue
        lines = [strip_comment(raw) for raw in text.splitlines()]
        for i, line in enumerate(lines):
            inline = REF_INLINE.match(line)
            if inline:
                refs.append((unquote(inline["key"]), path, i + 1))
                continue
            block = REF_BLOCK.match(line)
            if not block:
                continue
            # The key sits in the mapping this line opens. Blank lines and
            # stripped comments are not its end; a dedent is.
            for j in range(i + 1, len(lines)):
                nxt = lines[j]
                if not nxt.strip():
                    continue
                if len(nxt) - len(nxt.lstrip()) <= len(block["indent"]):
                    break
                key = KEY_LINE.match(nxt)
                if key:
                    refs.append((unquote(key["key"]), path, j + 1))
                    break
    return refs


def main() -> int:
    if not MANIFEST.is_file():
        print(f"missing {MANIFEST.relative_to(ROOT)}", file=sys.stderr)
        return 1

    optional = optional_secret_ids()
    refs = external_secret_refs()

    failures = [
        f"{secret!r} is optional ({MANIFEST.relative_to(ROOT)}:{optional[secret]}) "
        f"but read by an ExternalSecret ({path.relative_to(ROOT)}:{lineno}).\n"
        f"    Without a value it cannot sync, its target is never created, and "
        f"anything mounting that target will not start.\n"
        f"    Either drop the optional marker, or stop reading it through ESO."
        for secret, path, lineno in ((k, p, n) for k, p, n in refs if k in optional)
    ]

    if failures:
        print(f"{len(failures)} optional secret(s) treated as required:\n", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1

    print(
        f"ok: {len(optional)} optional secret(s), "
        f"{len(refs)} ExternalSecret reference(s), no conflicts."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
