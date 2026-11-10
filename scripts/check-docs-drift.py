#!/usr/bin/env python3
"""Check the counts in the layer READMEs against what the repo actually declares.

Several README sections are hand-written inventories of generated infrastructure:
the Pod Identity roles, the VPC endpoints, the Bedrock inference profiles and the
Argo CD app specs. Nothing forced them to agree with the Terraform, so they drifted
— in one case the same README disagreed with itself. Each check below pairs a
number in prose with the thing it claims to count.

Run from the repository root:  python3 scripts/check-docs-drift.py
Exit 0 = the docs match, exit 1 = drift, with the expected and actual values.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
failures: list[str] = []
checks = 0


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def claim(doc: str, pattern: str, label: str) -> int | None:
    """Pull the single number a README sentence claims, or record a failure."""
    found = re.findall(pattern, read(doc))
    if len(found) != 1:
        failures.append(
            f"{label}: expected exactly one sentence matching /{pattern}/ in {doc}, "
            f"found {len(found)}. Update the pattern in this script if the wording moved."
        )
        return None
    return int(found[0])


def compare(label: str, doc_value: int | None, real_value: int, how: str) -> None:
    global checks
    if doc_value is None:
        return
    checks += 1
    if doc_value != real_value:
        failures.append(f"{label}: README says {doc_value}, {how} is {real_value}")


# --- Pod Identity roles -----------------------------------------------------
associations = sum(
    len(re.findall(r'resource\s+"aws_eks_pod_identity_association"', p.read_text(encoding="utf-8")))
    for p in (ROOT / "05-compute/terraform").glob("*.tf")
)
compare(
    "Pod Identity roles",
    claim("05-compute/README.md", r"(\d+) IAM roles use the `pods\.eks\.amazonaws\.com`", "Pod Identity roles"),
    associations,
    "aws_eks_pod_identity_association count in 05-compute/terraform",
)

# --- VPC interface endpoints ------------------------------------------------
endpoints_tf = read("03-infrastructure/terraform/vpc-endpoints.tf")
interface_endpoints = len(re.findall(r'vpc_endpoint_type\s*=\s*"Interface"', endpoints_tf))
compare(
    "VPC interface endpoints",
    claim("03-infrastructure/README.md", r"\*\*Interface Endpoints\*\* \((\d+)\)", "VPC interface endpoints"),
    interface_endpoints,
    "Interface aws_vpc_endpoint count in 03-infrastructure/terraform/vpc-endpoints.tf",
)

# --- Bedrock application inference profiles ---------------------------------
variables_tf = read("04-data-and-ai/terraform/variables.tf")
block = re.search(
    r'variable\s+"bedrock_inference_profiles".*?\n  default = \{\n(.*?)\n  \}\n',
    variables_tf,
    re.S,
)
if block is None:
    failures.append(
        "Bedrock profiles: could not find the bedrock_inference_profiles default block "
        "in 04-data-and-ai/terraform/variables.tf"
    )
else:
    profiles = len(re.findall(r'^\s*"[^"]+"\s*=\s*\{', block.group(1), re.M))
    compare(
        "Bedrock inference profiles",
        claim("04-data-and-ai/README.md", r"\*\*Application Inference Profiles\*\*: (\d+) profiles", "Bedrock inference profiles"),
        profiles,
        "entries in the bedrock_inference_profiles default",
    )

# --- Argo CD app specs, per category ----------------------------------------
for category in ("System", "Chat", "Conduct"):
    directory = ROOT / "06-applications/sbx/apps" / category.lower()
    if not directory.is_dir():
        failures.append(f"{category} apps: {directory.relative_to(ROOT)} does not exist")
        continue
    compare(
        f"{category} apps",
        claim("06-applications/README.md", rf"### {category} Applications \((\d+)\)", f"{category} apps"),
        len(list(directory.glob("*.yaml"))),
        f"*.yaml files in 06-applications/sbx/apps/{category.lower()}",
    )

if failures:
    print("Documentation drift:\n")
    for f in failures:
        print(f"  - {f}")
    print(f"\n{len(failures)} problem(s). Update the README, or the repo, so they agree.")
    sys.exit(1)

print(f"All {checks} documented counts match the repository.")
