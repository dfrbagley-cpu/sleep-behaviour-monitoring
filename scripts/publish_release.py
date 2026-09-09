#!/usr/bin/env python3
"""Publish checked synthetic artifacts from this workflow after both OS jobs pass.

Runs only in the owner's GitHub Actions main-push release job. Uses its short-lived
GITHUB_TOKEN via gh. An existing published version is never overwritten.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import zipfile

REPOSITORY = "dfrbagley-cpu/sleep-behaviour-monitoring"
ROOT = Path(__file__).resolve().parents[1]


def version_from_source():
    match = re.search(r'^monitoring_version <- "([0-9]+\.[0-9]+\.[0-9]+)"$',
                      (ROOT / "R/config.R").read_text(), re.M)
    if not match:
        raise ValueError("Expected an explicit numeric release version.")
    return match.group(1)


def verify_package(path, edition, version):
    prefix = f"Sleep-Behaviour-{edition}-{version}"
    with zipfile.ZipFile(path) as archive:
        manifest = json.loads(archive.read(f"{prefix}/release-manifest.json"))
        if manifest["version"] != version or manifest["edition"] != edition:
            raise ValueError("Package manifest differs from the source version or edition.")
        expected = {f"{prefix}/{name}" for name in manifest["files"]}
        expected.add(f"{prefix}/release-manifest.json")
        if set(archive.namelist()) != expected or len(archive.namelist()) != len(expected):
            raise ValueError("Package contains unexpected or duplicate files.")
        for name, digest in manifest["files"].items():
            if name.startswith("/") or ".." in Path(name).parts:
                raise ValueError("Unsafe package member.")
            if hashlib.sha256(archive.read(f"{prefix}/{name}")).hexdigest() != digest:
                raise ValueError("Package checksum mismatch.")


def prepare_assets(downloaded, destination, version):
    destination.mkdir(parents=True, exist_ok=False)
    assets = []
    for edition in ("Hospital", "Advanced-Development"):
        filename = f"Sleep-Behaviour-{edition}-{version}.zip"
        source = downloaded / "dist" / filename
        verify_package(source, edition, version)
        target = destination / filename
        shutil.copyfile(source, target)
        assets.append(target)
    # These directories are created only by fixed --demo commands in the same
    # workflow. Receipts prevent accidentally treating a local-data run as a demo.
    demo_paths = (("ci-demo", "run-receipt.dcf"), ("ci-advanced", "research-receipt.dcf"))
    for folder, receipt in demo_paths:
        text = (downloaded / "outputs" / folder / receipt).read_text()
        if not re.search(r"^Synthetic:\s+TRUE\s*$", text, re.M):
            raise ValueError("Release examples must have an explicit synthetic receipt.")
    demos = destination / f"Sleep-Behaviour-Synthetic-Demos-{version}.zip"
    with zipfile.ZipFile(demos, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for folder, _ in demo_paths:
            directory = downloaded / "outputs" / folder
            for path in sorted(directory.iterdir()):
                if path.is_symlink() or not path.is_file() or path.suffix not in (".csv", ".html", ".xlsx", ".dcf"):
                    raise ValueError("Unexpected example artifact.")
                archive.write(path, f"{folder}/{path.name}")
    assets.append(demos)
    workbook = destination / f"Sleep-Behaviour-Synthetic-Workbook-{version}.xlsx"
    shutil.copyfile(downloaded / "outputs/ci-demo/monitoring-report.xlsx", workbook)
    assets.append(workbook)
    checksums = destination / "SHA256SUMS.txt"
    checksums.write_text("".join(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n" for path in assets))
    return assets + [checksums]


def gh(*arguments, capture=False):
    return subprocess.run(["gh", *arguments, "--repo", REPOSITORY], check=True,
                          text=True, capture_output=capture)


def ensure_tag_absent(tag):
    # --target is ignored by gh when a tag already exists. Refuse standalone
    # tags rather than attaching freshly built assets to an unrelated commit.
    tags = subprocess.run(["git", "ls-remote", "--tags", f"https://github.com/{REPOSITORY}.git",
                           f"refs/tags/{tag}"], check=True, text=True, capture_output=True)
    if tags.stdout.strip():
        raise SystemExit("This version tag already exists without a published release; inspect it before retrying.")


def main():
    if (os.environ.get("GITHUB_ACTIONS") != "true" or
        os.environ.get("GITHUB_REPOSITORY") != REPOSITORY or
        os.environ.get("GITHUB_EVENT_NAME") != "push" or
        os.environ.get("GITHUB_REF") != "refs/heads/main"):
        raise SystemExit("Publishing is restricted to this repository's checked main-push workflow.")
    head = os.environ.get("GITHUB_SHA", "")
    run_id = os.environ.get("GITHUB_RUN_ID", "")
    if not re.fullmatch(r"[0-9a-f]{40}", head) or not run_id.isdigit():
        raise SystemExit("Missing exact workflow commit or run identifier.")
    version = version_from_source()
    tag = f"v{version}"
    # A successful list distinguishes absence from permission/network errors.
    releases = json.loads(gh("release", "list", "--limit", "100", "--json", "tagName,isDraft", capture=True).stdout)
    existing = next((release for release in releases if release["tagName"] == tag), None)
    if existing:
        if existing["isDraft"]:
            raise SystemExit("An interrupted draft for this version exists; inspect it before retrying.")
        print(f"{tag} already published; existing release and assets are unchanged.")
        return
    ensure_tag_absent(tag)
    downloaded = ROOT / "release-download"
    gh("run", "download", run_id, "--name", "synthetic-report-ubuntu-latest", "--dir", str(downloaded))
    assets = prepare_assets(downloaded, ROOT / "release-assets", version)
    notes = ROOT / "docs/RELEASE_NOTES.md"
    # Draft first: readers cannot see a release until every asset upload succeeds.
    gh("release", "create", tag, "--target", head, "--draft", "--title",
       f"Sleep & Behaviour Monitoring {version} — public development preview", "--notes-file", str(notes))
    gh("release", "upload", tag, *(str(path) for path in assets))
    gh("release", "edit", tag, "--draft=false", "--latest")
    print(f"Published https://github.com/{REPOSITORY}/releases/tag/{tag}")


if __name__ == "__main__":
    main()
