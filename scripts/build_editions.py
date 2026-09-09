#!/usr/bin/env python3
"""Build both releases from one source tree; Python stdlib, no network or Git writes.

Only explicitly named files are included. Local data, outputs, .git and credentials
are never discovered or recursively copied. Run: python scripts/build_editions.py
"""
import hashlib
import json
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CORE = [f"R/{name}.R" for name in (
    "config", "synthetic", "analytics", "extended", "statistics", "raw_data",
    "report", "workbook", "pipeline", "import")]
HOSPITAL = CORE + [
    "run_hospital.R", "check_setup.R", "RUN_HOSPITAL.cmd",
    "hospital/settings.R", "hospital/START_HERE.md", "hospital/EXPORT_MAPPING.md",
    "config/site.example.dcf", "config/hospital.example.dcf",
    "docs/CONFIGURATION.md", "docs/MIGRATION.md", "docs/STATISTICS.md",
    "docs/SOURCE_REVIEW.md", "LICENSING.md", "CHANGELOG.md",
    "scripts/prepare_hospital_input.R", "config/import.example.dcf", "docs/IMPORT_ADAPTER.md"]
DEVELOPMENT = HOSPITAL + [
    "README.md", "run.R", "RUN_DEMO.cmd", "run-demo.bat", "docs/TWO_EDITIONS.md",
    ".gitattributes", ".gitignore", ".github/workflows/checks.yml",
    "scripts/build_editions.py", "scripts/install_optional.R",
    "tests/run_tests.R", "tests/test_extended.R", "tests/test_statistics.R",
    "tests/test_raw_config.R", "tests/test_editions.R", "tests/test_advanced.R",
    "advanced/run.R", "advanced/analysis.R", "advanced/report.R", "advanced/README.md",
    "advanced/research-policy.dcf", "docs/CASE_STUDY.md", "CONTRIBUTING.md", "SECURITY.md",
    "docs/RELEASE_NOTES.md", "docs/images/dashboard.png", "scripts/publish_release.py",
    "tests/test_import.R", "tests/test_release.py"]


def build():
    version = re.search(r'monitoring_version <- "([^"]+)"',
                        (ROOT / "R/config.R").read_text()).group(1)
    settings = (ROOT / "hospital/settings.R").read_text()
    settings_code = "\n".join(line.split("#", 1)[0] for line in settings.splitlines())
    expected_settings = (
        r'hospital_settings\s*<-\s*list\(\s*mode\s*=\s*"demo"\s*,\s*'
        r'input_file\s*=\s*""\s*,\s*config_file\s*=\s*"config/hospital.example.dcf"\s*,\s*'
        r'output_parent\s*=\s*"outputs"\s*\)'
    )
    if not re.fullmatch(expected_settings, settings_code.strip()):
        raise SystemExit("Release requires exactly the default synthetic hospital settings.")
    output = ROOT / "dist"
    output.mkdir(exist_ok=True)
    manifests = {}
    for edition, paths in (("Hospital", HOSPITAL), ("Advanced-Development", DEVELOPMENT)):
        files = {}
        for name in paths:
            source = ROOT / name
            if source.is_symlink():
                raise ValueError("Release sources must be regular files, not symbolic links.")
            content = source.read_bytes()
            # Canonical line endings make packages identical on Linux and Windows.
            if source.suffix in (".cmd", ".bat"):
                content = content.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
            elif source.suffix != ".png":
                content = content.replace(b"\r\n", b"\n")
            files[name] = content
        if edition == "Hospital":
            files["START_HERE.md"] = files["hospital/START_HERE.md"]
        manifest = {"version": version, "edition": edition,
                    "files": {name: hashlib.sha256(content).hexdigest()
                              for name, content in sorted(files.items())}}
        manifests[edition] = manifest
        files["release-manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode()
        archive = output / f"Sleep-Behaviour-{edition}-{version}.zip"
        prefix = f"Sleep-Behaviour-{edition}-{version}"
        with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as package:
            for name, content in sorted(files.items()):
                info = zipfile.ZipInfo(f"{prefix}/{name}", date_time=(2026, 9, 9, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o644 << 16
                package.writestr(info, content)
        with zipfile.ZipFile(archive) as package:
            assert package.testzip() is None
            assert all(hashlib.sha256(package.read(f"{prefix}/{name}")).hexdigest() == digest
                       for name, digest in manifest["files"].items())
            if edition == "Hospital":
                assert not any("/advanced/" in name or name.endswith("/run.R") for name in package.namelist())
        print(f"{archive}: {len(files)} files, {archive.stat().st_size} bytes")
    assert all(manifests["Hospital"]["files"][name] ==
               manifests["Advanced-Development"]["files"][name] for name in CORE)
    print("Shared core is byte-identical across editions; ZIP manifests verified.")


if __name__ == "__main__":
    build()
