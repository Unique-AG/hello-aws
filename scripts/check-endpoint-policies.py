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


def endpoints(text: str):
    """Yield (name, body) for each aws_vpc_endpoint block in the file."""
    starts = [(m.start(), m.group(1)) for m in RESOURCE.finditer(text)]
    for i, (pos, name) in enumerate(starts):
        end = starts[i + 1][0] if i + 1 < len(starts) else len(text)
        yield name, text[pos:end]


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


if __name__ == "__main__":
    sys.exit(main())
