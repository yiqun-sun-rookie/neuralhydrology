"""Deterministic, non-overwriting artifact primitives for formal version 09."""
from __future__ import annotations

from collections.abc import Mapping, Sequence
import hashlib
from importlib.metadata import distributions
import json
import os
from pathlib import Path
import platform
import stat
import subprocess
import sys
import uuid
from typing import Any

import numpy as np


def is_reparse_point(path: str | Path) -> bool:
    path = Path(path)
    try:
        status = os.lstat(path)
    except FileNotFoundError:
        return False
    attributes = int(getattr(status, "st_file_attributes", 0))
    reparse_flag = int(getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0))
    return stat.S_ISLNK(status.st_mode) or bool(reparse_flag and attributes & reparse_flag)


def assert_no_reparse_components(root: str | Path, target: str | Path) -> None:
    """Reject links, junctions, and paths that escape one trusted root."""
    root = Path(os.path.abspath(root))
    target = Path(os.path.abspath(target))
    if target != root and root not in target.parents:
        raise ValueError("target path escapes its trusted root")
    for ancestor in (root, *root.parents):
        if is_reparse_point(ancestor):
            raise ValueError(f"reparse point is forbidden above trusted root: {ancestor}")
    current = root
    for part in (None, *target.relative_to(root).parts):
        if part is not None:
            current = current / part
        if is_reparse_point(current):
            raise ValueError(f"reparse point is forbidden in trusted path: {current}")
    resolved_root = root.resolve(strict=False)
    resolved_target = target.resolve(strict=False)
    if resolved_target != resolved_root and resolved_root not in resolved_target.parents:
        raise ValueError("resolved target path escapes its trusted root")


def assert_no_embedded_seal_entries(sealed_files: Sequence[Mapping]) -> None:
    """Reject any sealed payload that attempts to include another seal file."""
    for item in sealed_files:
        if not isinstance(item, Mapping):
            raise ValueError("sealed file descriptor must be an object")
        relative_path = item.get("relative_path")
        if not isinstance(relative_path, str):
            raise ValueError("sealed file relative path is invalid")
        normalized_name = Path(relative_path.replace("\\", "/")).name.casefold()
        if normalized_name == "seal.json":
            raise ValueError("sealed payload cannot include a nested or replacement seal.json")


def assert_no_reparse_tree(root: str | Path) -> None:
    """Walk one directory without following links and reject every reparse entry."""
    root = Path(root)
    if is_reparse_point(root) or not root.is_dir():
        raise ValueError(f"artifact root must be a regular non-reparse directory: {root}")
    pending = [root]
    while pending:
        directory = pending.pop()
        with os.scandir(directory) as entries:
            for entry in entries:
                path = Path(entry.path)
                if is_reparse_point(path):
                    raise ValueError(f"reparse point is forbidden in artifact tree: {path}")
                if entry.is_dir(follow_symlinks=False):
                    pending.append(path)


def sha256_file(path: str | Path) -> str:
    """Return the SHA-256 of one regular file using bounded reads."""
    path = Path(path)
    if not path.is_file() or is_reparse_point(path):
        raise ValueError(f"hash input must be a regular non-link file: {path}")
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_json_bytes(value: Any) -> bytes:
    return json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        allow_nan=False,
    ).encode("utf-8")


def canonical_sha256(value: Any) -> str:
    return hashlib.sha256(canonical_json_bytes(value)).hexdigest()


def array_payload_sha256(array: np.ndarray) -> str:
    """Hash the exact C-order array payload without an NPY header."""
    value = np.asarray(array)
    if not value.flags.c_contiguous:
        raise ValueError("array payload must be C-contiguous")
    return hashlib.sha256(memoryview(value.view(np.uint8))).hexdigest()


def write_json_atomic(path: str | Path, value: Mapping) -> None:
    """Create strict JSON through an adjacent temporary file without overwriting."""
    path = Path(path)
    temporary = path.with_name(
        f".{path.name}.{os.getpid()}.{uuid.uuid4().hex}.tmp"
    )
    if path.exists():
        raise FileExistsError(f"JSON artifact already exists: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        with temporary.open("x", encoding="utf-8", newline="\n") as handle:
            json.dump(
                value,
                handle,
                indent=2,
                sort_keys=True,
                ensure_ascii=False,
                allow_nan=False,
            )
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.link(temporary, path)
        temporary.unlink()
    except BaseException:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass
        raise


def exact_file_inventory(root: str | Path, expected: Sequence[str]) -> list[dict]:
    """Return hashes only when a directory contains exactly the expected flat files."""
    root = Path(root)
    assert_no_reparse_tree(root)
    expected_paths = tuple(str(Path(value).as_posix()) for value in expected)
    if len(set(expected_paths)) != len(expected_paths):
        raise ValueError("expected inventory contains duplicate paths")
    actual = sorted(
        path.relative_to(root).as_posix()
        for path in root.rglob("*")
        if path.is_file()
    )
    if actual != sorted(expected_paths):
        raise ValueError(f"artifact inventory differs: expected {sorted(expected_paths)}, got {actual}")
    return [
        {
            "relative_path": relative,
            "size_bytes": (root / relative).stat().st_size,
            "sha256": sha256_file(root / relative),
        }
        for relative in expected_paths
    ]


def source_tree_manifest(root: str | Path, relative_paths: Sequence[str]) -> dict:
    """Bind an exact ordered list of executable source files to their bytes."""
    root = Path(root).resolve()
    paths = tuple(str(Path(value).as_posix()) for value in relative_paths)
    if not paths or len(set(paths)) != len(paths):
        raise ValueError("source paths must be nonempty and contain no duplicate")
    files = []
    for relative in paths:
        path = (root / relative).resolve()
        if root != path and root not in path.parents:
            raise ValueError("source path escapes the trusted root")
        files.append({"relative_path": relative, "sha256": sha256_file(path)})
    return {
        "schema": "exact_source_tree_v1",
        "files": files,
        "tree_sha256": canonical_sha256(files),
    }


def environment_fingerprint_v09(repo_root: str | Path) -> dict:
    """Capture the complete software environment relevant to deterministic input assembly."""
    import pandas as pd
    import psutil

    repo_root = Path(repo_root)
    installed_distributions = tuple(
        sorted(
            f"{distribution.metadata.get('Name', '<unnamed>')}=={distribution.version}"
            for distribution in distributions()
        )
    )
    installed_payload = "".join(
        f"{line}\n" for line in installed_distributions
    ).encode("utf-8")
    head = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=repo_root,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    tree = subprocess.run(
        ["git", "rev-parse", "HEAD^{tree}"],
        cwd=repo_root,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    status = subprocess.run(
        ["git", "status", "--porcelain", "--untracked-files=all"],
        cwd=repo_root,
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return {
        "git_head": head,
        "git_tree": tree,
        "git_clean": status == "",
        "python": platform.python_version(),
        "python_implementation": platform.python_implementation(),
        "python_executable": str(Path(sys.executable).resolve()),
        "platform": platform.platform(),
        "byteorder": sys.byteorder,
        "numpy": np.__version__,
        "pandas": pd.__version__,
        "psutil": psutil.__version__,
        "installed_distributions": list(installed_distributions),
        "installed_distributions_sha256": hashlib.sha256(installed_payload).hexdigest(),
    }


def promote_directory(
    building: str | Path,
    final: str | Path,
    *,
    trusted_root: str | Path | None = None,
) -> None:
    """Atomically rename one completed directory and never merge or overwrite."""
    building = Path(os.path.abspath(building))
    final = Path(os.path.abspath(final))
    boundary_root = Path(os.path.abspath(trusted_root)) if trusted_root is not None else building.parent
    assert_no_reparse_components(boundary_root, building)
    assert_no_reparse_components(boundary_root, final)
    assert_no_reparse_tree(building)
    if not building.is_dir():
        raise ValueError("building directory must be a regular directory")
    if final.exists() or is_reparse_point(final):
        raise FileExistsError(f"final directory already exists: {final}")
    if building.parent != final.parent:
        raise ValueError("building and final directories must share one parent")
    assert_no_reparse_components(boundary_root, building)
    assert_no_reparse_components(boundary_root, final)
    os.rename(building, final)
    assert_no_reparse_components(boundary_root, final)
    assert_no_reparse_tree(final)
