"""Load candidate descriptions used by the restricted runtime."""

from __future__ import annotations

import json
import math
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any


DESCRIPTOR_FIELDS = {
    "schema_version",
    "candidate_id",
    "category",
    "entrypoint",
    "dependencies",
    "allowed_reads",
    "outputs",
    "seed",
    "resources",
    "checkpoint",
    "resume",
}
ENTRYPOINT_COMMANDS = {"train", "predict"}
PREDICTION_READS = ("predict_features.parquet", "static_attributes.json", "model_artifacts")
TRAINING_READS = ("train_features.parquet", "train_targets.parquet", "static_attributes.json")
FROZEN_OUTPUTS = {"train": ("model_artifacts",), "predict": ("predictions.parquet",)}
DEPENDENCY_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*==[^<>=!~\s]+$")
CANDIDATE_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
CANDIDATE_CATEGORIES = {"deep_learning", "conceptual_rainfall_runoff", "fusion", "custom_python"}


@dataclass(frozen=True)
class CandidateDescriptor:
    schema_version: str
    candidate_id: str
    category: str
    entrypoint: dict[str, str]
    dependencies: tuple[str, ...]
    allowed_reads: dict[str, tuple[str, ...]]
    outputs: dict[str, tuple[str, ...]]
    seed: int
    resources: dict[str, Any]
    checkpoint: dict[str, Any]
    resume: dict[str, Any]


def load_and_validate_candidate_descriptor(
    path: str | Path, *, candidate_root: str | Path
) -> CandidateDescriptor:
    """Load a candidate descriptor whose declared entrypoints exist."""
    value = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError("candidate descriptor must be a JSON object")
    missing = DESCRIPTOR_FIELDS - set(value)
    if missing:
        raise ValueError(f"missing candidate descriptor fields: {sorted(missing)}")
    unknown = set(value) - DESCRIPTOR_FIELDS
    if unknown:
        raise ValueError(f"unknown candidate descriptor fields: {sorted(unknown)}")
    if value["schema_version"] != "candidate_descriptor_v1":
        raise ValueError("candidate descriptor schema mismatch")
    resources = value["resources"]
    resource_fields = {
        "cpu_cores",
        "gpu_count",
        "estimated_peak_memory_gb",
        "memory_safety_reserve_gb",
        "estimated_output_gb",
        "disk_safety_reserve_gb",
        "independent_monitor_enabled",
        "monitor_reason",
    }
    numeric_resource_fields = (
        "estimated_peak_memory_gb",
        "memory_safety_reserve_gb",
        "estimated_output_gb",
        "disk_safety_reserve_gb",
    )
    runtime_declarations_valid = (
        isinstance(value["candidate_id"], str)
        and CANDIDATE_ID_PATTERN.fullmatch(value["candidate_id"]) is not None
        and value["category"] in CANDIDATE_CATEGORIES
        and isinstance(value["seed"], int)
        and not isinstance(value["seed"], bool)
        and 0 <= value["seed"] <= 2**32 - 1
        and isinstance(resources, dict)
        and set(resources) == resource_fields
        and isinstance(resources.get("cpu_cores"), int)
        and not isinstance(resources.get("cpu_cores"), bool)
        and resources["cpu_cores"] >= 1
        and isinstance(resources.get("gpu_count"), int)
        and not isinstance(resources.get("gpu_count"), bool)
        and resources["gpu_count"] >= 0
        and all(
            isinstance(resources.get(field), (int, float))
            and not isinstance(resources.get(field), bool)
            and math.isfinite(resources[field])
            and resources[field] >= 0
            for field in numeric_resource_fields
        )
        and resources["estimated_peak_memory_gb"] > 0
        and isinstance(resources.get("independent_monitor_enabled"), bool)
        and isinstance(resources.get("monitor_reason"), str)
        and 0 < len(resources["monitor_reason"].strip()) <= 1024
        and value["checkpoint"] == {"supported": True, "staging_dir": "checkpoint_staging", "keep": "all"}
        and value["resume"] == {"supported": True}
    )
    if not runtime_declarations_valid:
        raise ValueError("candidate descriptor runtime declaration is invalid")
    if set(value["entrypoint"]) != ENTRYPOINT_COMMANDS:
        raise ValueError("entrypoint commands must be exactly train and predict")
    for dependency in value["dependencies"]:
        if not isinstance(dependency, str) or DEPENDENCY_PATTERN.fullmatch(dependency) is None:
            raise ValueError(f"dependency must pin one exact version: {dependency!r}")
    if tuple(value["allowed_reads"].get("train", ())) != TRAINING_READS:
        raise ValueError("training reads do not match the frozen contract")
    if tuple(value["allowed_reads"].get("predict", ())) != PREDICTION_READS:
        raise ValueError("prediction reads do not match the frozen contract")
    if {mode: tuple(paths) for mode, paths in value["outputs"].items()} != FROZEN_OUTPUTS:
        raise ValueError("candidate outputs do not match the frozen contract")
    root = Path(candidate_root).resolve()
    for entrypoint in value["entrypoint"].values():
        relative = Path(entrypoint)
        if relative.is_absolute() or ".." in relative.parts or relative == Path("."):
            raise ValueError(f"entrypoint must be a safe relative path: {entrypoint!r}")
        resolved = (root / relative).resolve()
        try:
            resolved.relative_to(root)
        except ValueError as error:
            raise ValueError(f"entrypoint must be a safe relative path: {entrypoint!r}") from error
        if not resolved.is_file():
            raise ValueError(f"candidate entrypoint does not exist: {entrypoint}")
    return CandidateDescriptor(
        schema_version=value["schema_version"],
        candidate_id=value["candidate_id"],
        category=value["category"],
        entrypoint=dict(value["entrypoint"]),
        dependencies=tuple(value["dependencies"]),
        allowed_reads={mode: tuple(paths) for mode, paths in value["allowed_reads"].items()},
        outputs={mode: tuple(paths) for mode, paths in value["outputs"].items()},
        seed=value["seed"],
        resources=dict(value["resources"]),
        checkpoint=dict(value["checkpoint"]),
        resume=dict(value["resume"]),
    )
