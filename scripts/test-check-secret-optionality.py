#!/usr/bin/env python3
"""Fixtures for check-secret-optionality.py: one per YAML form ESO accepts.

Every fixture declares an optional secret and then reads it through an
ExternalSecret, so the checker must fail. A form it cannot parse reports no
conflict and exits 0 -- the one failure mode a guard must not have, because it
turns "unchecked" into "checked and fine".

Run from anywhere:  python3 scripts/test-check-secret-optionality.py
"""

from __future__ import annotations

import contextlib
import importlib.util
import io
import tempfile
import unittest
from pathlib import Path

CHECKER = Path(__file__).resolve().parent / "check-secret-optionality.py"

MANIFEST = """\
secrets:
  - { name: google-search-api-key, kind: external, source: google_search, optional: true }
  - { name: argocd-github-app, kind: external, source: argocd_github_app }
"""

# Same conflict in each: an ExternalSecret reading the optional secret.
CONFLICTS = {
    "remoteRef opens the sequence item": """
resources:
  - kind: ExternalSecret
    spec:
      data:
        - remoteRef:
            key: google-search-api-key
          secretKey: api-key
""",
    "quoted kind": """
resources:
  - kind: "ExternalSecret"
    spec:
      data:
        - secretKey: api-key
          remoteRef:
            key: google-search-api-key
""",
    "dataFrom extract": """
resources:
  - kind: ExternalSecret
    spec:
      dataFrom:
        - extract:
            key: google-search-api-key
""",
    "comments between remoteRef and key": """
resources:
  - kind: ExternalSecret
    spec:
      data:
        - secretKey: api-key
          remoteRef:
            # one
            # two
            # three
            # four
            # five
            key: google-search-api-key
""",
    "quoted field names": """
resources:
  - kind: ExternalSecret
    spec:
      data:
        - secretKey: api-key
          "remoteRef":
            "key": google-search-api-key
""",
    "quoted field names, flow mapping": """
resources:
  - kind: ExternalSecret
    spec:
      data:
        - "remoteRef": {"key": google-search-api-key}
          secretKey: api-key
""",
    "flow mapping opened across lines": """
resources:
  - kind: ExternalSecret
    spec:
      data:
        - secretKey: api-key
          remoteRef: {
            key: google-search-api-key }
""",
    "trailing comment after the key": """
resources:
  - kind: ExternalSecret
    spec:
      data:
        - secretKey: api-key
          remoteRef:
            key: google-search-api-key  # optional integration
""",
}

# A required secret read the same way is the normal case and must pass.
CLEAN = """
resources:
  - kind: ExternalSecret
    spec:
      data:
        - secretKey: appID
          remoteRef:
            key: argocd-github-app
"""


def run_on(overlay: str, manifest: str = MANIFEST) -> int:
    """Exit code the checker returns for a tree holding just this overlay."""
    spec = importlib.util.spec_from_file_location("checker", CHECKER)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        apps = root / "06-applications"
        apps.mkdir()
        (apps / "secrets.yaml").write_text(manifest, encoding="utf-8")
        (apps / "overlay.yaml").write_text(overlay, encoding="utf-8")
        mod.ROOT = root
        mod.MANIFEST = apps / "secrets.yaml"
        mod.SEARCH_ROOT = apps
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return mod.main()


class ConflictingFormsAreCaught(unittest.TestCase):
    def test_each_form(self) -> None:
        for name, overlay in CONFLICTS.items():
            with self.subTest(form=name):
                self.assertEqual(
                    run_on(overlay), 1, f"{name}: conflict reported as clean"
                )

    def test_required_secret_passes(self) -> None:
        self.assertEqual(run_on(CLEAN), 0, "a required secret must not fail")

    def test_optional_secret_not_read_passes(self) -> None:
        self.assertEqual(run_on("resources: []"), 0, "no ExternalSecret, no conflict")

    def test_trailing_comment_on_the_declaration(self) -> None:
        manifest = MANIFEST.replace(
            "optional: true }", "optional: true }  # not configured here"
        )
        self.assertEqual(
            run_on(CONFLICTS["quoted kind"], manifest), 1,
            "a comment after the declaration hid the optional marker",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
