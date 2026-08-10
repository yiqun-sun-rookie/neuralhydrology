"""Materialize one category-specific candidate source tree without aliases."""

from __future__ import annotations

import json
import os
import shutil
from dataclasses import dataclass
from pathlib import Path

from unified_autoresearch.runtime.descriptor import (
    CandidateDescriptor,
    load_and_validate_candidate_descriptor,
)


REFERENCE_CATEGORIES = (
    "deep_learning",
    "conceptual_rainfall_runoff",
    "fusion",
    "custom_python",
)
PINNED_DEPENDENCIES = ("numpy==1.26.4", "pandas==2.3.3", "pyarrow==22.0.0")
# The cluster cannot reach the set above. Its conda cannot create environments, its glibc 2.17
# limits it to manylinux2014 wheels, and pandas 2.3.3 is not published on the package index at
# all -- the original pin is only satisfiable from a conda channel. This second set is the
# closest one that installs there: numpy is identical, pandas and pyarrow step back.
#
# It also has to avoid numpy 2.x, whose import calls ctypes.dlopen, which the candidate sandbox
# denies by design. Relaxing that denial to accommodate a library version would trade away a
# real isolation property, so the dependency set moves instead of the sandbox.
#
# Written out here rather than read from the interpreter: a declaration derived from the
# environment would agree with that environment by construction and check nothing.
PINNED_DEPENDENCIES_CLUSTER = ("numpy==1.26.4", "pandas==2.2.3", "pyarrow==17.0.0")
FROZEN_DEPENDENCY_SETS = (PINNED_DEPENDENCIES, PINNED_DEPENDENCIES_CLUSTER)


def _frozen_dependencies(dependencies: tuple[str, ...]) -> list[str]:
    if tuple(dependencies) not in FROZEN_DEPENDENCY_SETS:
        raise ValueError("dependency set is not one of the frozen declarations")
    return list(dependencies)


def _io_path(path: str | Path) -> str:
    resolved = str(Path(path).resolve())
    if os.name != "nt" or resolved.startswith("\\\\?\\"):
        return resolved
    if resolved.startswith("\\\\"):
        return "\\\\?\\UNC\\" + resolved[2:]
    return "\\\\?\\" + resolved


def _copy_file_long_path_safe(source: str | Path, destination: str | Path) -> None:
    shutil.copy2(_io_path(source), _io_path(destination))


@dataclass(frozen=True)
class MaterializedReferenceCandidate:
    source_root: Path
    descriptor_path: Path
    descriptor: CandidateDescriptor


def _descriptor_value(category: str, dependencies: tuple[str, ...]) -> dict:
    candidate_id = f"reference-{category.replace('_', '-')}-v1"
    return {
        "schema_version": "candidate_descriptor_v1",
        "candidate_id": candidate_id,
        "category": category,
        "entrypoint": {"train": "entrypoint.py", "predict": "entrypoint.py"},
        "dependencies": _frozen_dependencies(dependencies),
        "allowed_reads": {
            "train": ["train_features.parquet", "train_targets.parquet", "static_attributes.json"],
            "predict": ["predict_features.parquet", "static_attributes.json", "model_artifacts"],
        },
        "outputs": {"train": ["model_artifacts"], "predict": ["predictions.parquet"]},
        "seed": 29,
        "resources": {
            "cpu_cores": 1,
            "gpu_count": 0,
            "estimated_peak_memory_gb": 0.35,
            "memory_safety_reserve_gb": 0.25,
            "estimated_output_gb": 0.01,
            "disk_safety_reserve_gb": 0.1,
            "independent_monitor_enabled": False,
            "monitor_reason": "short lightweight development reference candidate; no heavy workload",
        },
        "checkpoint": {"supported": True, "staging_dir": "checkpoint_staging", "keep": "all"},
        "resume": {"supported": True},
    }


def _hbv_lite_descriptor_value(dependencies: tuple[str, ...]) -> dict:
    """The first real candidate declares a supervised, longer-running workload."""
    return {
        "schema_version": "candidate_descriptor_v1",
        "candidate_id": "hbv-lite-calibrated-v1",
        "category": "conceptual_rainfall_runoff",
        "entrypoint": {"train": "entrypoint.py", "predict": "entrypoint.py"},
        "dependencies": _frozen_dependencies(dependencies),
        "allowed_reads": {
            "train": ["train_features.parquet", "train_targets.parquet", "static_attributes.json"],
            "predict": ["predict_features.parquet", "static_attributes.json", "model_artifacts"],
        },
        "outputs": {"train": ["model_artifacts"], "predict": ["predictions.parquet"]},
        "seed": 29,
        "resources": {
            "cpu_cores": 1,
            "gpu_count": 0,
            "estimated_peak_memory_gb": 1.0,
            "memory_safety_reserve_gb": 0.5,
            "estimated_output_gb": 0.05,
            "disk_safety_reserve_gb": 0.5,
            "independent_monitor_enabled": True,
            "monitor_reason": "first real candidate; per-basin calibration runs long enough to need supervision",
        },
        "checkpoint": {"supported": True, "staging_dir": "checkpoint_staging", "keep": "all"},
        "resume": {"supported": True},
    }


def materialize_hbv_lite_candidate(
    *, output_root: str | Path, dependencies: tuple[str, ...] = PINNED_DEPENDENCIES
) -> MaterializedReferenceCandidate:
    """Copy the calibrated HBV-lite method plus the common runtime into a new root."""
    descriptor_value = _hbv_lite_descriptor_value(dependencies)  # validates before touching disk
    root = Path(output_root).resolve()
    if root.exists():
        raise FileExistsError(root)
    root.mkdir(parents=True)
    package_root = Path(__file__).resolve().parent
    _copy_file_long_path_safe(package_root / "templates" / "entrypoint.py", root / "entrypoint.py")
    _copy_file_long_path_safe(package_root / "templates" / "runtime_common.py", root / "runtime_common.py")
    _copy_file_long_path_safe(package_root / "implementations" / "hbv_lite.py", root / "method.py")
    descriptor_path = root / "candidate-descriptor.json"
    descriptor_path.write_text(
        json.dumps(descriptor_value, indent=2, sort_keys=True, allow_nan=False) + "\n",
        encoding="utf-8",
    )
    descriptor = load_and_validate_candidate_descriptor(descriptor_path, candidate_root=root)
    return MaterializedReferenceCandidate(
        source_root=root,
        descriptor_path=descriptor_path,
        descriptor=descriptor,
    )


def materialize_reference_candidate(
    *,
    category: str,
    output_root: str | Path,
    dependencies: tuple[str, ...] = PINNED_DEPENDENCIES,
) -> MaterializedReferenceCandidate:
    """Copy exactly one reference method plus its common runtime into a new root."""
    if category not in REFERENCE_CATEGORIES:
        raise ValueError(f"unknown reference candidate category: {category!r}")
    descriptor_value = _descriptor_value(category, dependencies)  # validates before touching disk
    root = Path(output_root).resolve()
    if root.exists():
        raise FileExistsError(root)
    root.mkdir(parents=True)
    package_root = Path(__file__).resolve().parent
    _copy_file_long_path_safe(package_root / "templates" / "entrypoint.py", root / "entrypoint.py")
    _copy_file_long_path_safe(package_root / "templates" / "runtime_common.py", root / "runtime_common.py")
    _copy_file_long_path_safe(package_root / "implementations" / f"{category}.py", root / "method.py")
    descriptor_path = root / "candidate-descriptor.json"
    descriptor_path.write_text(
        json.dumps(descriptor_value, indent=2, sort_keys=True, allow_nan=False) + "\n",
        encoding="utf-8",
    )
    descriptor = load_and_validate_candidate_descriptor(descriptor_path, candidate_root=root)
    return MaterializedReferenceCandidate(
        source_root=root,
        descriptor_path=descriptor_path,
        descriptor=descriptor,
    )
