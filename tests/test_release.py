#!/usr/bin/env python3
"""Release gates: no public mutation, no external tools, only synthetic fixtures."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("publish_release", ROOT / "scripts/publish_release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseChecks(unittest.TestCase):
    def package(self, directory, edition, altered=False):
        version = "1.2.3"
        prefix = f"Sleep-Behaviour-{edition}-{version}"
        path = directory / f"{prefix}.zip"
        manifest = {"version": version, "edition": edition,
                    "files": {"R/core.R": hashlib.sha256(b"reviewed source").hexdigest()}}
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr(f"{prefix}/R/core.R", b"modified source" if altered else b"reviewed source")
            archive.writestr(f"{prefix}/release-manifest.json", json.dumps(manifest))
        return path

    def fixture(self, directory, synthetic=True):
        (directory / "dist").mkdir()
        for edition in ("Hospital", "Advanced-Development"):
            self.package(directory / "dist", edition)
        for name, receipt in (("ci-demo", "run-receipt.dcf"), ("ci-advanced", "research-receipt.dcf")):
            folder = directory / "outputs" / name
            folder.mkdir(parents=True)
            (folder / receipt).write_text("Synthetic: " + ("TRUE" if synthetic else "FALSE") + "\n")
            (folder / "report.html").write_text("<p>Synthetic fixture</p>")
        (directory / "outputs/ci-demo/monitoring-report.xlsx").write_bytes(b"synthetic workbook fixture")

    def test_modified_package_cannot_reach_release_assets(self):
        with tempfile.TemporaryDirectory() as folder:
            path = self.package(Path(folder), "Hospital", altered=True)
            with self.assertRaisesRegex(ValueError, "checksum"):
                release.verify_package(path, "Hospital", "1.2.3")

    def test_real_data_receipt_blocks_example_publication(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.fixture(root, synthetic=False)
            with self.assertRaisesRegex(ValueError, "synthetic receipt"):
                release.prepare_assets(root, root / "public", "1.2.3")

    def test_assets_are_named_and_checksummed_for_exact_version(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.fixture(root)
            assets = release.prepare_assets(root, root / "public", "1.2.3")
            self.assertEqual(len(assets), 5)
            for line in (root / "public/SHA256SUMS.txt").read_text().splitlines():
                digest, name = line.split("  ", 1)
                self.assertEqual(hashlib.sha256((root / "public" / name).read_bytes()).hexdigest(), digest)
            with zipfile.ZipFile(root / "public/Sleep-Behaviour-Synthetic-Demos-1.2.3.zip") as archive:
                self.assertEqual(len(archive.namelist()), 5)
                self.assertTrue(all(name.startswith(("ci-demo/", "ci-advanced/")) for name in archive.namelist()))

    def test_local_execution_cannot_publish(self):
        with patch.dict(os.environ, {}, clear=True), patch.object(release, "gh") as command:
            with self.assertRaisesRegex(SystemExit, "restricted"):
                release.main()
            command.assert_not_called()

    def test_standalone_tag_cannot_receive_new_assets(self):
        with patch.object(release.subprocess, "run", return_value=SimpleNamespace(stdout="other-commit refs/tags/v1.2.3\n")):
            with self.assertRaisesRegex(SystemExit, "already exists"):
                release.ensure_tag_absent("v1.2.3")


if __name__ == "__main__":
    unittest.main()
