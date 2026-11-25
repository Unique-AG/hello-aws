"""Fail when any aws_vpc_endpoint declares no policy, or a null or empty one.

Run from the repository root; see docs/security-baseline.md for why.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Layers that may declare endpoints. Add to this list, do not widen the glob:
# an accidental match in an unrelated layer would report a phantom endpoint.
SOURCES = [
    "03-infrastructure/terraform/vpc-endpoints.tf",
    "04-data-and-ai/terraform/vpc-endpoints.tf",
]

RESOURCE = re.compile(r'^resource\s+"aws_vpc_endpoint"\s+"([A-Za-z0-9_]+)"\s*\{', re.M)
# Exactly two spaces, so this is the resource's own attribute and not one
# nested deeper. A null or empty value is no policy at all.
POLICY = re.compile(r"^\s{2}policy\s*=\s*(?!null\b)(?!\"\"\s*$)\S", re.M)


def _body(text: str, open_brace: int) -> str:
    """Return the resource block starting at its opening brace, brace-matched.

    Counting has to ignore braces inside quoted strings, or a value such as
    jsonencode containing a literal brace would end the block early or late.
    """
    depth, i, n = 0, open_brace, len(text)
    in_str = False
    while i < n:
        c = text[i]
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return text[open_brace : i + 1]
        i += 1
    return text[open_brace:]


def endpoints(text: str):
    """Yield (name, body) per aws_vpc_endpoint, each body its own block only."""
    for m in RESOURCE.finditer(text):
        brace = text.index("{", m.start())
        yield m.group(1), _body(text, brace)


def main() -> int:
    missing: list[str] = []
    checked = 0

    for rel in SOURCES:
        path = ROOT / rel
        if not path.exists():
            print(f"{rel}: not found — the check cannot confirm anything.")
            return 1
        text = path.read_text(encoding="utf-8")
        found = list(endpoints(text))
        if not found:
            print(f"{rel}: no aws_vpc_endpoint found — the parser is broken, not the tree.")
            return 1
        for name, body in found:
            checked += 1
            if not POLICY.search(body):
                missing.append(f"{rel}: aws_vpc_endpoint.{name}")

    if missing:
        print("VPC endpoints without a policy:\n")
        for m in missing:
            print(f"  - {m}")
        print(
            f"\n{len(missing)} of {checked} endpoint(s) allow any principal that can reach "
            "them to call the whole service.\nGive each a policy, or state why it cannot "
            "have one in docs/security-baseline.md and add it to this check."
        )
        return 1

    print(f"All {checked} VPC endpoints declare a policy.")
    return 0


def selftest() -> int:
    """Cases the check has already been wrong about, so it cannot regress."""
    EP = 'resource "aws_vpc_endpoint" "a" {\n  vpc_id = x\n%s}\n'
    cases = [
        ("policy present", EP % "  policy = local.p\n", []),
        ("policy null", EP % "  policy = null\n", ["a"]),
        ("policy empty", EP % '  policy = ""\n', ["a"]),
        ("no policy", EP % "", ["a"]),
        ("nested policy only", EP % "  lifecycle {\n    policy = x\n  }\n", ["a"]),
        # The body must stop at its own brace: otherwise this IAM resource's
        # policy is read as the endpoint's and the gap passes unseen.
        (
            "policy-less endpoint followed by an IAM policy",
            EP % "" + 'resource "aws_iam_role_policy" "r" {\n  policy = data.x.json\n}\n',
            ["a"],
        ),
        (
            "jsonencode braces and a quoted brace do not end the block",
            'resource "aws_vpc_endpoint" "a" {\n  tags = { N = "{" }\n'
            "  policy = jsonencode({ S = [{ E = \"Allow\" }] })\n}\n",
            [],
        ),
    ]
    bad = 0
    for label, text, want in cases:
        got = [n for n, b in endpoints(text) if not POLICY.search(b)]
        ok = got == want
        bad += 0 if ok else 1
        print(f"  {'ok  ' if ok else 'FAIL'} {label}: missing={got} want={want}")
    print("selftest passed." if not bad else f"{bad} selftest case(s) failed.")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(selftest() if "--selftest" in sys.argv else main())
