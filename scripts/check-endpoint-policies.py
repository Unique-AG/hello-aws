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


CLOSE = re.compile(r"^\}$", re.M)


def _body(text: str, start: int) -> str:
    """Resource body, ending at the first line that is exactly a closing brace.

    `terraform fmt` puts a top-level block's closing brace alone at column 0,
    and the validate job enforces it, so no tokenizer is needed here.
    """
    m = CLOSE.search(text, start)
    return text[start : m.end()] if m else text[start:]


def endpoints(text: str):
    """Yield (name, body) per aws_vpc_endpoint, each body its own block only."""
    for m in RESOURCE.finditer(text):
        yield m.group(1), _body(text, m.start())


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
        # A brace inside a comment is not a delimiter: one truncates the body
        # and rejects a valid endpoint, the other swallows the next resource.
        (
            "a commented closing brace does not truncate the body",
            'resource "aws_vpc_endpoint" "a" {\n  # }\n  policy = local.p\n}\n',
            [],
        ),
        (
            "a commented opening brace does not swallow the next resource",
            'resource "aws_vpc_endpoint" "a" {\n  # {\n}\n'
            'resource "aws_iam_role_policy" "r" {\n  policy = data.x.json\n}\n',
            ["a"],
        ),
        (
            "a quoted comment marker inside an interpolation is not a comment",
            'resource "aws_vpc_endpoint" "a" {\n  tags = { N = "vpce-${"/*"}" }\n}\n'
            'resource "aws_iam_role_policy" "r" {\n  policy = data.x.json\n}\n',
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
