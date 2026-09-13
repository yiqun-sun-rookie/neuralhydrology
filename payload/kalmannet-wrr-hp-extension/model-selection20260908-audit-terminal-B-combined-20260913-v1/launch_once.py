"""Single-use admission guard for one immutable model-selection training run."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath

from study_config import REMOTE_FAMILY_ROOT, make_combos, remote_stage_root, validate_combo, validate_index


REMOTE_STAGE_ROOTS = {stage: Path(remote_stage_root(stage)) for stage in ("A", "B")}
EXPERIMENT_REL = Path("experiments/optimize_hyper_parameters/wrr_hp_extension_20260902")
SOURCE_MANIFEST_REL = EXPERIMENT_REL / "source_manifest.json"
BASE_CONFIG_REL = EXPERIMENT_REL / "base_config.yaml"
ORIGINAL_LAUNCHER_REL = EXPERIMENT_REL / "run_one_cell.py"
SOURCE_ARCHIVE_SHA256 = "266eab5e5f2b21b992d218aaede11abc6018c11a23c3c5c28a328bd5210a497e"
SOURCE_EXTERNAL_MANIFEST_SHA256 = "8e9aa0c3769c050c070c6f48f1faa41aab94994f1a0791e89e35b92a44a8181e"
BASE_CONFIG_SHA256 = "de3cdb625d849370ea6fcc8c911d2d62f0e5cdea16e9ac371e9d16cbe388dd64"
ORIGINAL_LAUNCHER_SHA256 = "c71621dca168a9f7a2b8c87e3f3d8a5bce392037c58ef6bbc1123c6cb09c2626"
EXPECTED_RUNTIME_SHA256 = "28be078ba0f5e2bd3a5db30669ef95b044e592e8dd8f090a7736d5aaf7e2c296"
FULL_RUNTIME_FIELDS = (
    "python_version", "numpy_version", "torch_version", "cuda_version", "cudnn_version", "gpu",
    "deterministic_algorithms", "cudnn_deterministic", "cudnn_benchmark",
)
VERSION_RUNTIME_FIELDS = (
    "python_version", "numpy_version", "torch_version", "cuda_version", "cudnn_version", "gpu",
)


def sha256_path(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _safe_relative_path(value: str) -> Path:
    if not isinstance(value, str) or not value or "\\" in value or re.match(r"^[A-Za-z]:", value):
        raise RuntimeError(f"unsafe static path: {value!r}")
    if value.startswith("/") or any(part in ("", ".", "..") for part in value.split("/")):
        raise RuntimeError(f"unsafe static path: {value!r}")
    pure = PurePosixPath(value)
    if pure.is_absolute():
        raise RuntimeError(f"unsafe static path: {value!r}")
    return Path(*pure.parts)


def identify_stage_root(root: Path) -> str:
    resolved = root.resolve()
    matches = [stage for stage, expected in REMOTE_STAGE_ROOTS.items() if resolved == expected.resolve()]
    if len(matches) != 1:
        raise RuntimeError(f"stage root identity mismatch: {root}")
    return matches[0]


def verify_stage_root(root: Path, stage: str, manifest: dict) -> None:
    required = REMOTE_STAGE_ROOTS[stage]
    if root.resolve() != required.resolve():
        raise RuntimeError(f"stage root identity mismatch: running {root}, required {required}")
    if manifest.get("stage") != stage:
        raise RuntimeError(f"manifest stage mismatch: expected {stage}, got {manifest.get('stage')!r}")
    if manifest.get("remote_root") != str(required).replace("\\", "/"):
        raise RuntimeError("manifest remote root identity mismatch")


def verify_manifest_contract(stage: str, manifest: dict) -> None:
    rows = make_combos(stage)
    expected_archive = f"payload/stage_{stage}.tar.gz"
    checks = {
        "schema_version": 1,
        "study": "neural_gain_model_selection",
        "stage": stage,
        "candidate_count": len(rows),
        "allowed_indices": list(range(len(rows))),
        "remote_family_root": str(REMOTE_STAGE_ROOTS[stage]).replace("\\", "/").rsplit("/stages/", 1)[0],
    }
    for field, expected in checks.items():
        if manifest.get(field) != expected:
            raise RuntimeError(f"manifest field {field} mismatch")
    archive = manifest.get("archive", {})
    if archive.get("relative_path") != expected_archive or not archive.get("members_are_relative_to_stage_root"):
        raise RuntimeError("manifest archive contract mismatch")
    if not re.fullmatch(r"[0-9a-f]{64}", str(archive.get("sha256", ""))) or not isinstance(archive.get("size_bytes"), int):
        raise RuntimeError("manifest archive identity is malformed")
    baseline = manifest.get("source_baseline", {})
    expected_baseline = {
        "archive_sha256": SOURCE_ARCHIVE_SHA256,
        "external_manifest_sha256": SOURCE_EXTERNAL_MANIFEST_SHA256,
        "base_config_sha256": BASE_CONFIG_SHA256,
        "original_launcher_sha256": ORIGINAL_LAUNCHER_SHA256,
    }
    for field, expected in expected_baseline.items():
        if baseline.get(field) != expected:
            raise RuntimeError(f"manifest source baseline {field} mismatch")
    runtime = manifest.get("expected_runtime", {})
    if runtime.get("path") != "expected_runtime.json" or runtime.get("sha256") != EXPECTED_RUNTIME_SHA256:
        raise RuntimeError("manifest expected runtime identity mismatch")


def verify_static_files(root: Path, manifest: dict) -> None:
    expected = manifest.get("static_files")
    if not isinstance(expected, dict) or not expected:
        raise RuntimeError("stage manifest has no static_files")
    required = {
        "study_config.py", "launch_once.py", "hpc_array.slurm", "expected_runtime.json",
        f"repo/{SOURCE_MANIFEST_REL.as_posix()}", f"repo/{BASE_CONFIG_REL.as_posix()}",
        f"repo/{ORIGINAL_LAUNCHER_REL.as_posix()}",
    }
    if not required.issubset(expected):
        raise RuntimeError(f"stage manifest lacks required static files: {sorted(required - set(expected))}")
    for rel, expected_hash in expected.items():
        path = root / _safe_relative_path(rel)
        if not path.is_file() or path.is_symlink():
            raise RuntimeError(f"static file missing or non-regular: {rel}")
        actual = sha256_path(path)
        if actual != expected_hash:
            raise RuntimeError(f"static SHA-256 mismatch for {rel}: expected {expected_hash}, got {actual}")


def verify_source_hashes(root: Path, manifest: dict) -> None:
    repo = root / "repo"
    source_manifest_path = repo / SOURCE_MANIFEST_REL
    packaged = manifest.get("packaged_source_manifest", {})
    if packaged.get("path") != f"repo/{SOURCE_MANIFEST_REL.as_posix()}":
        raise RuntimeError("packaged source manifest path mismatch")
    if sha256_path(source_manifest_path) != packaged.get("sha256"):
        raise RuntimeError("packaged source manifest SHA-256 mismatch")
    source_manifest = json.loads(source_manifest_path.read_text(encoding="utf-8"))
    if source_manifest.get("model_selection_stage") != manifest.get("stage"):
        raise RuntimeError("inner source manifest stage mismatch")
    if source_manifest.get("derived_from_archive_sha256") != SOURCE_ARCHIVE_SHA256:
        raise RuntimeError("inner source manifest archive provenance mismatch")
    if source_manifest.get("derived_from_external_manifest_sha256") != SOURCE_EXTERNAL_MANIFEST_SHA256:
        raise RuntimeError("inner source manifest external provenance mismatch")
    expected = source_manifest.get("source_sha256")
    if not isinstance(expected, dict) or not expected:
        raise RuntimeError("inner source manifest has no source_sha256")
    for rel, expected_hash in expected.items():
        path = repo / _safe_relative_path(rel)
        if not path.is_file() or path.is_symlink():
            raise RuntimeError(f"inner source file missing or non-regular: {rel}")
        actual = sha256_path(path)
        if actual != expected_hash:
            raise RuntimeError(f"inner source SHA-256 mismatch for {rel}: expected {expected_hash}, got {actual}")
    if sha256_path(repo / BASE_CONFIG_REL) != BASE_CONFIG_SHA256:
        raise RuntimeError("base configuration SHA-256 mismatch")
    if sha256_path(repo / ORIGINAL_LAUNCHER_REL) != ORIGINAL_LAUNCHER_SHA256:
        raise RuntimeError("original launcher SHA-256 mismatch")


def validate_runtime_snapshot(snapshot: dict, expected: dict, fields=FULL_RUNTIME_FIELDS) -> None:
    for field in fields:
        if field not in expected:
            raise RuntimeError(f"expected_runtime.json is missing {field}")
        if snapshot.get(field) != expected[field]:
            raise RuntimeError(f"runtime mismatch for {field}: expected {expected[field]!r}, got {snapshot.get(field)!r}")


def inspect_environment() -> dict:
    import numpy
    import torch

    gpu = torch.cuda.get_device_name(0) if torch.cuda.is_available() else None
    return {
        "python_version": ".".join(str(part) for part in sys.version_info[:3]),
        "numpy_version": numpy.__version__,
        "torch_version": torch.__version__,
        "cuda_version": torch.version.cuda,
        "cudnn_version": torch.backends.cudnn.version(),
        "gpu": gpu,
        "deterministic_algorithms": torch.are_deterministic_algorithms_enabled(),
        "cudnn_deterministic": torch.backends.cudnn.deterministic,
        "cudnn_benchmark": torch.backends.cudnn.benchmark,
    }


def load_original_launcher(path: Path):
    spec = importlib.util.spec_from_file_location("frozen_wrr_original_launcher", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"unable to load original launcher: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def refuse_existing_output(output: Path) -> None:
    if os.path.lexists(output):
        raise FileExistsError(f"output already exists: {output}")


def claim_once(root: Path, stage: str, combo: dict) -> Path:
    claims = root / "claims"
    if os.path.lexists(claims) and (claims.is_symlink() or not claims.is_dir()):
        raise FileExistsError(f"claims path is not a real directory: {claims}")
    claims.mkdir(exist_ok=True)
    path = claims / f"index{int(combo['index']):04d}.json"
    payload = {
        "stage": stage,
        "index": int(combo["index"]),
        "seed": int(combo["seed"]),
        "effective_seed": int(combo["effective_seed"]),
        "run_id": combo["run_id"],
        "job_id": os.environ.get("SLURM_JOB_ID"),
        "array_task_id": os.environ.get("SLURM_ARRAY_TASK_ID"),
        "claimed_at": datetime.now(timezone.utc).isoformat(),
    }
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(payload, stream, indent=2, sort_keys=True)
        stream.write("\n")
    return path


def _load_controls(root: Path, stage: str) -> tuple[dict, dict]:
    manifest_path = root / f"STAGE_{stage}_MANIFEST.json"
    if not manifest_path.is_file() or manifest_path.is_symlink():
        raise RuntimeError(f"stage manifest missing or non-regular: {manifest_path.name}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    verify_stage_root(root, stage, manifest)
    verify_manifest_contract(stage, manifest)
    verify_static_files(root, manifest)
    verify_source_hashes(root, manifest)
    runtime_path = root / "expected_runtime.json"
    if sha256_path(runtime_path) != EXPECTED_RUNTIME_SHA256:
        raise RuntimeError("expected runtime SHA-256 mismatch")
    expected_runtime = json.loads(runtime_path.read_text(encoding="utf-8"))
    if not isinstance(expected_runtime.get("provenance_note"), str) or not expected_runtime["provenance_note"].strip():
        raise RuntimeError("expected_runtime.json is missing provenance_note")
    return manifest, expected_runtime


def run_one(root: Path, index: int) -> None:
    root = root.resolve()
    stage = identify_stage_root(root)
    index = validate_index(stage, index)
    _manifest, expected_runtime = _load_controls(root, stage)
    environment = inspect_environment()
    validate_runtime_snapshot(environment, expected_runtime, VERSION_RUNTIME_FIELDS)

    experiment = root / "repo" / EXPERIMENT_REL
    original = load_original_launcher(experiment / "run_one_cell.py")
    combo = original.load_combo(index)
    validate_combo(stage, index, combo)
    original.guard_source_contract()
    original.guard_data_contract()

    out_base = experiment / "runs" / f"formal_seed{int(combo['seed'])}"
    output = original.expected_run_dir(Path(str(out_base) + "_gpu"), combo)
    refuse_existing_output(output)
    claim_once(root, stage, combo)

    unchanged_configure = original.configure_reproducibility
    expected_seed = int(combo["effective_seed"])

    def configure_and_validate(seed: int) -> dict:
        if isinstance(seed, bool) or int(seed) != expected_seed:
            raise RuntimeError(f"effective seed mismatch: expected {expected_seed}, got {seed}")
        runtime = unchanged_configure(seed)
        if runtime.get("seed") != expected_seed:
            raise RuntimeError(f"effective seed mismatch after seeding: expected {expected_seed}, got {runtime.get('seed')}")
        snapshot = dict(runtime)
        snapshot.update(
            {
                "python_version": environment["python_version"],
                "numpy_version": environment["numpy_version"],
            }
        )
        validate_runtime_snapshot(snapshot, expected_runtime)
        return runtime

    original.configure_reproducibility = configure_and_validate
    old_argv = sys.argv[:]
    try:
        sys.argv = [str(experiment / "run_one_cell.py"), "--index", str(index)]
        original.main()
    finally:
        sys.argv = old_argv
        original.configure_reproducibility = unchanged_configure


def main() -> None:
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--check-environment", action="store_true")
    group.add_argument("--index", type=int)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    stage = identify_stage_root(root)
    _manifest, expected = _load_controls(root, stage)
    if args.check_environment:
        validate_runtime_snapshot(inspect_environment(), expected, VERSION_RUNTIME_FIELDS)
        print(f"EXPECTED_RUNTIME_MATCH stage={stage}")
        return
    run_one(root, args.index)


if __name__ == "__main__":
    main()

