"""Fail when a VPC endpoint has no policy, or one that constrains only the caller.

Rules and exemptions: docs/security-baseline.md. Run from the repository root.
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

# A policy that constrains the resource, not only the caller. Anchored on the
# assignment: a mention in a comment must not read as the policy in force.
PERIMETER = re.compile(
    r"^\s{2}policy\s*=\s*local\.(?:interface_endpoint_policy_with_resources|sts_endpoint_policy)\b",
    re.M,
)
GATEWAY = re.compile(r'vpc_endpoint_type\s*=\s*"Gateway"')

# Endpoints that cannot carry a resource condition, with the reason. A resource
# condition denies an ARN outside the organization, and these legitimately reach
# AWS-owned ones. Remove an entry and the check demands the perimeter again.
PRINCIPAL_ONLY = {
    "ecr_api": "pulls EKS add-on images from AWS-owned registry accounts and the public.ecr.aws upstream",
    "ecr_dkr": "as ecr_api: layer pulls resolve to AWS-owned registries",
    "bedrock": "foundation-model ARNs carry no account, so no organization owns them",
    "bedrock_runtime": "as bedrock",
    "bedrock_agentcore": "as bedrock",
    "bedrock_agentcore_gateway": "as bedrock",
    "ec2": "RunInstances names the AMI it launches, and the node and management-server images are Amazon-owned",
    "ssm": "AWS-owned documents, including AWS-StartPortForwardingSessionToRemoteHost",
    "ssm_messages": "session data plane for AWS-owned documents",
    "ec2_messages": "session data plane for AWS-owned documents",
}
# Exactly two spaces, so this is the resource's own attribute and not one
# nested deeper. A null or empty value is no policy at all.
POLICY = re.compile(r"^\s{2}policy\s*=\s*(?!null\b)(?!\"\"\s*$)\S", re.M)


# A top-level closing brace, optionally with the trailing comment fmt keeps.
CLOSE = re.compile(r"^\}[ \t]*(?:(?:#|//).*)?$", re.M)


def _body(text: str, start: int) -> str:
    """Ends at the first top-level closing brace, which `terraform fmt` guarantees."""
    m = CLOSE.search(text, start)
    return text[start : m.end()] if m else text[start:]


def endpoints(text: str):
    """Yield (name, body) per aws_vpc_endpoint, each body its own block only."""
    for m in RESOURCE.finditer(text):
        yield m.group(1), _body(text, m.start())


def main() -> int:
    missing: list[str] = []
    unscoped: list[str] = []
    seen_interface: set[str] = set()
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
                continue
            if GATEWAY.search(body):
                continue  # a gateway endpoint carries its own tailored policy
            seen_interface.add(name)
            if not PERIMETER.search(body) and name not in PRINCIPAL_ONLY:
                unscoped.append(f"{rel}: aws_vpc_endpoint.{name}")

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

    if unscoped:
        print("Interface endpoints whose policy checks the caller but not the resource:\n")
        for u in unscoped:
            print(f"  - {u}")
        print(
            "\nUse local.interface_endpoint_policy_with_resources, or add the endpoint to "
            "PRINCIPAL_ONLY in this script with the AWS-owned resource it must reach."
        )
        return 1

    stale = sorted(set(PRINCIPAL_ONLY) - seen_interface)
    if stale:
        print("PRINCIPAL_ONLY names endpoints that no longer exist:\n")
        for n in stale:
            print(f"  - {n}")
        print("\nRemove them, or the next endpoint of that name inherits an exemption nobody granted.")
        return 1

    print(
        f"All {checked} VPC endpoints declare a policy; "
        f"{len(seen_interface) - len(PRINCIPAL_ONLY)} of {len(seen_interface)} interface "
        f"endpoints also limit the resources reachable through them."
    )
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
            "a closing brace with a trailing comment still ends the body",
            'resource "aws_vpc_endpoint" "a" {\n  vpc_id = "x"\n} # endpoint a\n'
            'resource "aws_vpc_endpoint" "b" {\n  policy = local.p\n}\n',
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

    # The resource-perimeter rule. `want` is the endpoints that should be
    # reported as checking the caller but not the resource.
    perimeter_cases = [
        (
            "principal-only interface endpoint is reported",
            'resource "aws_vpc_endpoint" "a" {\n  policy = local.interface_endpoint_policy\n}\n',
            ["a"],
        ),
        (
            "resource-scoped interface endpoint passes",
            'resource "aws_vpc_endpoint" "a" {\n  policy = local.interface_endpoint_policy_with_resources\n}\n',
            [],
        ),
        (
            "the sts policy counts as resource-scoped",
            'resource "aws_vpc_endpoint" "a" {\n  policy = local.sts_endpoint_policy\n}\n',
            [],
        ),
        (
            "a gateway endpoint is not subject to the rule",
            'resource "aws_vpc_endpoint" "a" {\n  vpc_endpoint_type = "Gateway"\n  policy = jsonencode({})\n}\n',
            [],
        ),
        # interface_endpoint_policy is a prefix of the _with_resources name, so a
        # substring test would read the stronger policy as the weaker one.
        (
            "the longer local name is not mistaken for the shorter",
            'resource "aws_vpc_endpoint" "a" {\n  policy = local.interface_endpoint_policy_with_resources # was local.interface_endpoint_policy\n}\n',
            [],
        ),
        # A comment naming the stronger local must not stand in for using it.
        (
            "a comment mentioning the perimeter policy is not the policy",
            'resource "aws_vpc_endpoint" "a" {\n  # TODO: interface_endpoint_policy_with_resources\n  policy = local.interface_endpoint_policy\n}\n',
            ["a"],
        ),
    ]
    for label, text, want in perimeter_cases:
        got = [
            n
            for n, b in endpoints(text)
            if POLICY.search(b) and not GATEWAY.search(b) and not PERIMETER.search(b)
        ]
        ok = got == want
        bad += 0 if ok else 1
        print(f"  {'ok  ' if ok else 'FAIL'} {label}: unscoped={got} want={want}")

    print("selftest passed." if not bad else f"{bad} selftest case(s) failed.")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(selftest() if "--selftest" in sys.argv else main())
