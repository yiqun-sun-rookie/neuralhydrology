"""Build a complete SHA-256 experiment fingerprint from auditable components."""

from __future__ import annotations

import hashlib
import importlib.metadata
import json
import os
import platform
import subprocess
from functools import lru_cache
from pathlib import Path
from typing import Any, Iterable


COMPONENT_NAMES = (
    "git_commit",
    "code",
    "uncommitted_diff",
    "configuration",
    "dependencies",
    "data_manifest",
    "random_seeds",
    "artifacts",
)

def _canonical_bytes(value: Any) -> bytes:
    return json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False
    ).encode("utf-8")


def _digest(value: Any) -> str:
    return hashlib.sha256(_canonical_bytes(value)).hexdigest()


def _io_path(path: str | Path) -> str:
    raw = str(path)
    if os.name == "nt" and raw.startswith("\\\\?\\"):
        return raw
    absolute = str(Path(path).resolve())
    if os.name != "nt":
        return absolute
    if absolute.startswith("\\\\"):
        return "\\\\?\\UNC\\" + absolute[2:]
    return "\\\\?\\" + absolute


def _path_from_io_path(path: str) -> Path:
    if os.name != "nt":
        return Path(path)
    if path.startswith("\\\\?\\UNC\\"):
        return Path("\\\\" + path[8:])
    if path.startswith("\\\\?\\"):
        return Path(path[4:])
    return Path(path)


def _walk_files(root: Path) -> list[Path]:
    return [
        Path(os.path.join(directory, filename))
        for directory, _, filenames in os.walk(_io_path(root))
        for filename in filenames
    ]


def _sha256_file(path: Path) -> str:
    before = os.stat(_io_path(path))
    digest = hashlib.sha256()
    with open(_io_path(path), "rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    after = os.stat(_io_path(path))
    if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
        raise RuntimeError(f"file changed while fingerprinting: {path}")
    return digest.hexdigest()


def _relative(root: Path, path: Path) -> str:
    try:
        return _path_from_io_path(str(path)).relative_to(root).as_posix()
    except ValueError as error:
        raise ValueError(f"fingerprint path is outside repository root: {path}") from error


def _manifest(root: Path, paths: Iterable[str | Path]) -> list[dict[str, Any]]:
    files: dict[str, Path] = {}
    for raw_path in paths:
        path = Path(raw_path).resolve()
        physical = Path(_io_path(path))
        if not os.path.exists(physical):
            raise FileNotFoundError(path)
        candidates = [physical] if os.path.isfile(physical) else _walk_files(path)
        for candidate in candidates:
            if (
                not os.path.isfile(candidate)
                or "__pycache__" in candidate.parts
                or candidate.suffix in {".pyc", ".pyo"}
            ):
                continue
            label = _relative(root, candidate)
            if label == ".git" or label.startswith(".git/"):
                continue
            files[label] = candidate
    return [
        {
            "path": label,
            "bytes": os.stat(_io_path(files[label])).st_size,
            "sha256": _sha256_file(files[label]),
        }
        for label in sorted(files)
    ]


def _git(repo_root: Path, *args: str) -> bytes:
    result = subprocess.run(
        ["git", *args], cwd=repo_root, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    return result.stdout


def _uncommitted_details(
    repo_root: Path,
    *,
    git_diff_path: str | Path | None = None,
    git_status_path: str | Path | None = None,
    untracked_scope_paths: Iterable[str | Path] | None = None,
) -> dict[str, Any]:
    current_diff = _git(repo_root, "diff", "--binary", "HEAD", "--", ".")
    current_status = _git(repo_root, "status", "--porcelain=v1", "-z", "--untracked-files=all")
    if (git_diff_path is None) != (git_status_path is None):
        raise ValueError("saved Git difference and status paths must be provided together")
    if git_diff_path is None:
        diff = current_diff
        status = current_status
    else:
        with open(_io_path(git_diff_path), "rb") as stream:
            diff = stream.read()
        with open(_io_path(git_status_path), "rb") as stream:
            status = stream.read()
        if diff != current_diff or status != current_status:
            raise RuntimeError("saved Git state differs from the repository at fingerprint time")
    untracked_output = _git(repo_root, "ls-files", "--others", "--exclude-standard", "-z", "--", ".")
    untracked_paths = [item.decode("utf-8") for item in untracked_output.split(b"\0") if item]
    if untracked_scope_paths is None:
        untracked_manifest = _manifest(repo_root, [repo_root / path for path in untracked_paths])
    else:
        untracked_labels = set(untracked_paths)
        scoped_manifest = _manifest(repo_root, untracked_scope_paths)
        untracked_manifest = [entry for entry in scoped_manifest if entry["path"] in untracked_labels]
    return {
        "git_diff_sha256": hashlib.sha256(diff).hexdigest(),
        "git_status_sha256": hashlib.sha256(status).hexdigest(),
        "untracked_manifest": untracked_manifest,
    }


@lru_cache(maxsize=1)
def _environment_inventory() -> dict[str, Any]:
    packages = sorted(
        {
            (
                (distribution.metadata.get("Name") or "unknown").lower(),
                distribution.version,
            )
            for distribution in importlib.metadata.distributions()
        }
    )
    return {
        "python": platform.python_version(),
        "implementation": platform.python_implementation(),
        "platform": platform.platform(),
        "packages": [{"name": name, "version": version} for name, version in packages],
    }


def build_fingerprint(
    *,
    repo_root: str | Path,
    code_paths: Iterable[str | Path],
    configuration_paths: Iterable[str | Path],
    dependency_paths: Iterable[str | Path],
    data_manifest_paths: Iterable[str | Path],
    random_seeds: list[int],
    artifact_paths: Iterable[str | Path],
    git_diff_path: str | Path | None = None,
    git_status_path: str | Path | None = None,
    untracked_scope_paths: Iterable[str | Path] | None = None,
) -> dict[str, Any]:
    """Return component hashes, evidence details, and one root SHA-256."""
    root = Path(repo_root).resolve()
    if not (root / ".git").exists():
        raise ValueError(f"repository root does not contain .git: {root}")

    git_commit = _git(root, "rev-parse", "HEAD").decode("ascii").strip()
    code_manifest = _manifest(root, code_paths)
    uncommitted = _uncommitted_details(
        root,
        git_diff_path=git_diff_path,
        git_status_path=git_status_path,
        untracked_scope_paths=untracked_scope_paths,
    )
    configuration_manifest = _manifest(root, configuration_paths)
    dependency_details = {
        "files": _manifest(root, dependency_paths),
        "environment": _environment_inventory(),
    }
    data_manifest = _manifest(root, data_manifest_paths)
    artifact_roots = [Path(path).resolve() for path in artifact_paths]
    if not artifact_roots or any(not path.is_dir() for path in artifact_roots):
        raise ValueError("artifact paths must be directory roots")
    artifact_manifest = _manifest(root, artifact_roots)
    if not artifact_manifest:
        raise ValueError("artifact directory roots contain no files")
    seeds = [int(seed) for seed in random_seeds]

    details = {
        "git_commit": git_commit,
        "code": code_manifest,
        "uncommitted_diff": uncommitted,
        "configuration": configuration_manifest,
        "dependencies": dependency_details,
        "data_manifest": data_manifest,
        "random_seeds": seeds,
        "artifacts": artifact_manifest,
    }
    components = {name: _digest(value) for name, value in details.items()}
    root_sha256 = _digest({"schema_version": "experiment_fingerprint_v1", "components": components})
    return {
        "schema_version": "experiment_fingerprint_v1",
        "components": components,
        "root_sha256": root_sha256,
        "details": details,
    }


def validate_fingerprint(fingerprint: dict[str, Any]) -> None:
    """Reject missing, malformed, internally inconsistent, or forged fingerprint payloads."""
    if fingerprint.get("schema_version") != "experiment_fingerprint_v1":
        raise ValueError("unsupported fingerprint schema")
    components = fingerprint.get("components")
    details = fingerprint.get("details")
    if not isinstance(components, dict) or set(components) != set(COMPONENT_NAMES):
        raise ValueError("fingerprint components are incomplete")
    if not isinstance(details, dict) or set(details) != set(COMPONENT_NAMES):
        raise ValueError("fingerprint details are incomplete")
    for name in COMPONENT_NAMES:
        value = components[name]
        try:
            valid_hex = isinstance(value, str) and len(value) == 64 and len(bytes.fromhex(value)) == 32
        except ValueError:
            valid_hex = False
        if not valid_hex:
            raise ValueError(f"fingerprint component is not SHA-256: {name}")
        if _digest(details[name]) != value:
            raise ValueError(f"fingerprint component detail mismatch: {name}")
    expected_root = _digest({"schema_version": "experiment_fingerprint_v1", "components": components})
    if fingerprint.get("root_sha256") != expected_root:
        raise ValueError("fingerprint root mismatch")
