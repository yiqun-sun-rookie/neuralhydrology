"""Run the ten-task CAMELS parameter-path mechanism check.

This entry point is deliberately narrower than the registered large-sample
runner: it accepts exactly ten already-selected design-seed tasks and executes
the existing baseline and observation-postcollapse path method in one common
fail-fast batch.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import platform
import sys
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path

import pandas as pd
import numpy as np

from camels_switch_confirmation.batch_control import execute_fail_fast
from camels_switch_confirmation.g1_precheck import (
    PARAM_KEYS,
    STATE_NAMES as HYDRO_STATE_NAMES,
)
from camels_switch_confirmation.g2_switch_confirmation import _run_one
from hbv_joint_uncertainty.hbv_adapter import STATE_NAMES as FULL_STATE_NAMES


_REPO_ROOT = Path(__file__).resolve().parents[2]

CONFIGURATION_STATUS = "mechanism_check_design_seeds_not_validation"
RESULTS_RELATIVE_ROOT = Path("results") / "23_camels_switch_confirmation"
PROTECTED_EVIDENCE_EXPERIMENTS = frozenset(
    {
        "camels_parfc_transition_path_03_mechanism10_s01_20260810_local",
        "camels_parfc_transition_path_03a_mechanism10_s01_20260810_local",
    }
)
EXPECTED_RUNTIME_SEMANTICS = {
    "python_version": (
        "3.11.5 | packaged by Anaconda, Inc. | "
        "(main, Sep 11 2023, 13:26:23) [MSC v.1916 64 bit (AMD64)]"
    ),
    "python_implementation": "cpython",
    "python_compiler": "MSC v.1916 64 bit (AMD64)",
    "machine": "AMD64",
    "numpy_version": "1.26.4",
    "byteorder": "little",
    "double_format": "IEEE, little-endian",
    "float_radix": 2,
    "float_mant_dig": 53,
    "float_rounds": 1,
    "ulp_one_hex": "0x1.0000000000000p-52",
    "ulp_zero_hex": "0x0.0000000000001p-1022",
    "nextafter_zero_hex": "0x0.0000000000001p-1022",
    "math_fma_available": False,
}
EXPECTED_FILTER = {
    "q_scale": 3e-8,
    "q_structure": "lower_groundwater_state_only",
    "q_mode": "fixed",
    "q_state_multiplier": 1.0,
    "observation_variance_multiplier": 1.0,
}
EXPECTED_ARMS = (
    {
        "arm_id": "C",
        "interaction_mode": "full",
        "parameter_state_mapping": "conservative_parfc",
    },
    {
        "arm_id": "P",
        "interaction_mode": "pairwise_path_postcollapse",
        "parameter_state_mapping": "conservative_parfc",
    },
)
REQUIRED_IMPLEMENTATION_ROLES = frozenset(
    {
        "g2_switch_confirmation",
        "imm",
        "hbv_state_mapping",
        "preflight",
        "hbv_adapter",
        "sigma_filter",
        "bank",
        "g1_precheck",
        "data_loader",
        "hbv_model_and_bounds",
        "batch_control",
        "mechanism_runner",
        "mechanism_tests",
        "preregistration",
        "mechanism_plan",
        "mechanism_verifier",
        "mechanism_verifier_tests",
    }
)
TASK_COLUMNS = frozenset(
    {
        "basin_id",
        "seed",
        "arm_id",
        "source_probability_path",
        "source_probability_bytes",
        "source_probability_sha256",
    }
)
SOURCE_REQUIRED_FIELDS = frozenset(
    {
        "probabilities",
        "log_probabilities",
        "truth_q",
        "observations",
        "basin_id",
        "seed",
        "arm_id",
        "state_interaction_mode",
        "parameter_state_mapping",
        "filter_process_variance_scale",
        "filter_process_covariance_structure",
        "filter_q_mode",
        "filter_q_state_multiplier",
        "filter_observation_variance_multiplier",
    }
)


@dataclass(frozen=True)
class VerifiedMechanismRun:
    configuration: dict
    config_path: Path
    config_sha256: str
    task_table: pd.DataFrame
    task_table_path: Path
    task_table_sha256: str
    parameter_rows: dict[str, dict]
    data_root: Path
    output_root: Path
    implementation_hashes: dict[str, str]
    input_hashes: dict[str, str | int]
    runtime_contract: dict[str, object]


def sha256_file(path: str | Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _observed_runtime_contract() -> dict[str, object]:
    """Return the exact floating runtime used by the registered path calculation."""
    executable = Path(sys.executable).resolve()
    return {
        "python_executable": str(executable),
        "python_executable_sha256": sha256_file(executable),
        "python_version": sys.version,
        "python_implementation": sys.implementation.name,
        "python_compiler": platform.python_compiler(),
        "machine": platform.machine(),
        "numpy_version": np.__version__,
        "byteorder": sys.byteorder,
        "double_format": float.__getformat__("double"),
        "float_radix": sys.float_info.radix,
        "float_mant_dig": sys.float_info.mant_dig,
        "float_rounds": sys.float_info.rounds,
        "ulp_one_hex": math.ulp(1.0).hex(),
        "ulp_zero_hex": math.ulp(0.0).hex(),
        "nextafter_zero_hex": math.nextafter(0.0, 1.0).hex(),
        "math_fma_available": hasattr(math, "fma"),
    }


def _verify_runtime_contract(config: Mapping) -> dict[str, object]:
    """Reject any runtime drift before an output directory can be created."""
    registered = config.get("runtime")
    if not isinstance(registered, Mapping):
        raise ValueError("runtime must be a mapping")
    observed = _observed_runtime_contract()
    for key, fixed_value in EXPECTED_RUNTIME_SEMANTICS.items():
        observed_value = observed.get(key)
        registered_value = registered.get(key)
        if observed_value != fixed_value or registered_value != fixed_value:
            raise ValueError(
                f"fixed runtime semantics changed for {key}: "
                f"required {fixed_value!r}, registered {registered_value!r}, "
                f"observed {observed_value!r}"
            )
    if set(registered) != set(observed):
        missing = sorted(set(observed).difference(registered))
        extra = sorted(set(registered).difference(observed))
        raise ValueError(
            f"runtime fields changed: missing={missing}, extra={extra}"
        )
    for key, expected in registered.items():
        actual = observed[key]
        if expected == actual:
            continue
        if key == "python_executable_sha256":
            raise ValueError(
                "Python executable SHA-256 changed: "
                f"expected {expected}, observed {actual}"
            )
        raise ValueError(
            f"runtime contract changed for {key}: "
            f"expected {expected!r}, observed {actual!r}"
        )
    return observed


def _relative_path(root: Path, value: object, label: str) -> Path:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{label} must be a nonempty repository-relative path")
    relative = Path(value)
    if relative.is_absolute() or relative.drive or ".." in relative.parts:
        raise ValueError(
            f"{label} must be a repository-relative path without parent traversal"
        )
    return root / relative


def _registered_file(root: Path, value: object, label: str) -> Path:
    path = _relative_path(root, value, label)
    if not path.is_file():
        raise FileNotFoundError(f"{label} is missing: {path}")
    return path


def _is_within(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
    except ValueError:
        return False
    return True


def _verify_output_root(
    root: Path,
    outputs: Mapping,
    tasks: pd.DataFrame,
) -> Path:
    """Keep a new run isolated from the worktree boundary and frozen evidence."""
    resolved_root = root.resolve()
    allowed_parent = (resolved_root / RESULTS_RELATIVE_ROOT).resolve()
    if not _is_within(allowed_parent, resolved_root):
        raise ValueError("registered results root resolves outside the repository root")

    output_root = _relative_path(
        resolved_root,
        outputs.get("root"),
        "output root",
    ).resolve()
    if output_root == allowed_parent or not _is_within(output_root, allowed_parent):
        raise ValueError(
            "output root must resolve inside a new experiment directory under "
            f"{RESULTS_RELATIVE_ROOT.as_posix()}"
        )

    protected_roots = {
        (allowed_parent / experiment).resolve()
        for experiment in PROTECTED_EVIDENCE_EXPERIMENTS
    }
    for value in tasks["source_probability_path"]:
        source = _relative_path(
            resolved_root,
            value,
            "source probability",
        ).resolve()
        if not _is_within(source, allowed_parent):
            continue
        relative_source = source.relative_to(allowed_parent)
        if relative_source.parts:
            protected_roots.add((allowed_parent / relative_source.parts[0]).resolve())

    for protected_root in protected_roots:
        if output_root == protected_root or _is_within(output_root, protected_root):
            raise ValueError(
                "output root must not be inside a protected source or prior-evidence "
                f"experiment: {protected_root}"
            )
    if output_root.exists():
        raise FileExistsError(f"output root already exists: {output_root}")
    return output_root


def _verify_file_hash(path: Path, expected: object, label: str) -> str:
    observed = sha256_file(path)
    if observed != str(expected):
        raise ValueError(
            f"{label} SHA-256 changed: expected {expected}, observed {observed}"
        )
    return observed


def _normalize_basin_id(value: object) -> str:
    text = str(value).strip().zfill(8)
    if len(text) != 8 or not text.isdigit():
        raise ValueError(f"invalid basin identifier: {value}")
    return text


def _source_scalar(archive, field: str, source: Path):
    value = archive[field]
    if value.shape != ():
        raise ValueError(
            f"source probability embedded {field} must be scalar: {source}"
        )
    return value.item()


def _verify_source_probability_content(source: Path, task) -> None:
    try:
        with np.load(source, allow_pickle=False) as archive:
            missing = sorted(SOURCE_REQUIRED_FIELDS.difference(archive.files))
            if missing:
                raise ValueError(
                    "source probability NPZ lacks required fields: "
                    + ", ".join(missing)
                )
            scalar_contract = {
                "basin_id": str(task.basin_id),
                "seed": int(task.seed),
                "arm_id": "C",
                "state_interaction_mode": "full",
                "parameter_state_mapping": "conservative_parfc",
                "filter_process_variance_scale": 3e-8,
                "filter_process_covariance_structure": (
                    "lower_groundwater_state_only"
                ),
                "filter_q_mode": "fixed",
                "filter_q_state_multiplier": 1.0,
                "filter_observation_variance_multiplier": 1.0,
            }
            for field, expected in scalar_contract.items():
                observed = _source_scalar(archive, field, source)
                if observed != expected:
                    raise ValueError(
                        f"source probability embedded {field} differs for "
                        f"{task.basin_id} seed {task.seed}: expected "
                        f"{expected!r}, observed {observed!r}"
                    )

            expected_shapes = {
                "probabilities": (1260, 3),
                "log_probabilities": (1260, 3),
                "truth_q": (1260,),
                "observations": (1260,),
            }
            arrays = {}
            for field, expected_shape in expected_shapes.items():
                value = np.asarray(archive[field])
                if value.shape != expected_shape:
                    raise ValueError(
                        f"source probability {field} shape differs for "
                        f"{task.basin_id} seed {task.seed}: expected "
                        f"{expected_shape}, observed {value.shape}"
                    )
                if not np.issubdtype(value.dtype, np.number):
                    raise ValueError(
                        f"source probability {field} must be numeric: {source}"
                    )
                if not np.isfinite(value).all():
                    raise ValueError(
                        f"source probability {field} contains non-finite values: "
                        f"{source}"
                    )
                arrays[field] = value.astype(float, copy=False)
            probabilities = arrays["probabilities"]
            log_probabilities = arrays["log_probabilities"]
            if (probabilities < 0).any() or (probabilities > 1).any():
                raise ValueError("source probabilities must lie between zero and one")
            if not np.allclose(
                probabilities.sum(axis=1),
                1.0,
                rtol=0.0,
                atol=1e-12,
            ):
                raise ValueError("source probabilities are not normalized")
            if not np.allclose(
                np.exp(log_probabilities),
                probabilities,
                rtol=0.0,
                atol=1e-12,
            ):
                raise ValueError(
                    "source probabilities and log_probabilities do not agree"
                )
    except ValueError:
        raise
    except Exception as error:  # noqa: BLE001 - convert archive errors to a stop
        raise ValueError(f"source probability NPZ is unreadable: {source}") from error


def _verify_implementation(root: Path, config: Mapping) -> dict[str, str]:
    implementation = config.get("implementation")
    if not isinstance(implementation, Mapping):
        raise ValueError("implementation must be a mapping")
    missing_roles = sorted(REQUIRED_IMPLEMENTATION_ROLES.difference(implementation))
    if missing_roles:
        raise ValueError(
            "implementation mapping lacks required roles: " + ", ".join(missing_roles)
        )
    hashes: dict[str, str] = {}
    paths: set[Path] = set()
    for role, entry in implementation.items():
        if not isinstance(role, str) or not isinstance(entry, Mapping):
            raise ValueError("implementation entries must be named mappings")
        path = _registered_file(root, entry.get("path"), f"implementation file {role}")
        resolved = path.resolve()
        if resolved in paths:
            raise ValueError("implementation mapping contains duplicate file paths")
        paths.add(resolved)
        observed = sha256_file(path)
        expected = str(entry.get("sha256"))
        if observed != expected:
            raise ValueError(
                f"implementation file SHA-256 changed for {role}: "
                f"expected {expected}, observed {observed}"
            )
        hashes[role] = observed
    return hashes


def _verify_filter_and_arms(config: Mapping) -> None:
    filter_config = config.get("filter")
    if not isinstance(filter_config, Mapping) or any(
        filter_config.get(key) != expected
        for key, expected in EXPECTED_FILTER.items()
    ):
        raise ValueError("fixed filter contract changed")
    arms = config.get("arms")
    if not isinstance(arms, list) or tuple(arms) != EXPECTED_ARMS:
        raise ValueError("fixed arms contract changed")


def _verify_tasks(root: Path, inputs: Mapping) -> tuple[pd.DataFrame, Path, str]:
    task_path = _registered_file(root, inputs.get("task_table"), "task table")
    observed_hash = sha256_file(task_path)
    expected_hash = str(inputs.get("task_table_sha256"))
    if observed_hash != expected_hash:
        raise ValueError(
            "task table SHA-256 changed: "
            f"expected {expected_hash}, observed {observed_hash}"
        )
    tasks = pd.read_csv(
        task_path,
        dtype={"basin_id": str, "arm_id": str},
        keep_default_na=False,
    )
    missing = sorted(TASK_COLUMNS.difference(tasks.columns))
    if missing:
        raise ValueError("task table lacks required columns: " + ", ".join(missing))
    tasks = tasks.copy()
    tasks["basin_id"] = [_normalize_basin_id(value) for value in tasks["basin_id"]]
    numeric_seed = pd.to_numeric(tasks["seed"], errors="coerce")
    if numeric_seed.isna().any() or any(float(value) != int(value) for value in numeric_seed):
        raise ValueError("task seeds must be integers")
    tasks["seed"] = numeric_seed.astype(int)
    if not set(tasks["seed"]).issubset({0, 1}):
        raise ValueError("design seeds must be only 0 or 1")
    pairs = list(zip(tasks["basin_id"], tasks["seed"]))
    if len(tasks) != 10 or len(set(pairs)) != 10:
        raise ValueError("task table must contain exactly 10 unique basin-seed tasks")
    if not (tasks["arm_id"] == "C").all():
        raise ValueError("task source arm must be C")

    for row in tasks.itertuples(index=False):
        source = _registered_file(
            root,
            row.source_probability_path,
            f"source probability file {row.basin_id} seed {row.seed}",
        )
        try:
            expected_bytes = int(row.source_probability_bytes)
        except (TypeError, ValueError) as error:
            raise ValueError("source probability byte count must be an integer") from error
        observed_bytes = source.stat().st_size
        if observed_bytes != expected_bytes:
            raise ValueError(
                f"source probability byte count changed for {row.basin_id} seed "
                f"{row.seed}: expected {expected_bytes}, observed {observed_bytes}"
            )
        observed_source_hash = sha256_file(source)
        if observed_source_hash != str(row.source_probability_sha256):
            raise ValueError(
                f"source probability SHA-256 changed for {row.basin_id} seed "
                f"{row.seed}: expected {row.source_probability_sha256}, "
                f"observed {observed_source_hash}"
            )
        _verify_source_probability_content(source, row)
    return tasks.reset_index(drop=True), task_path, observed_hash


def _verify_initial_moment_manifest(
    root: Path,
    inputs: Mapping,
    tasks: pd.DataFrame,
) -> tuple[Path, str, int]:
    """Verify independently registered day-zero moments for all ten tasks."""
    path = _registered_file(
        root,
        inputs.get("initial_moment_manifest"),
        "initial moment manifest",
    )
    observed_hash = sha256_file(path)
    expected_hash = str(inputs.get("initial_moment_manifest_sha256"))
    if observed_hash != expected_hash:
        raise ValueError(
            "initial moment manifest SHA-256 changed: "
            f"expected {expected_hash}, observed {observed_hash}"
        )
    required = {
        "basin_id",
        "seed",
        "initial_probabilities",
        "initial_states",
        "initial_covariances",
        "initial_probability_axis_order",
        "initial_state_axis_order",
        "initial_covariance_axis_order",
    }
    try:
        with np.load(path, allow_pickle=False) as archive:
            missing = sorted(required.difference(archive.files))
            if missing:
                raise ValueError(
                    "initial moment manifest lacks fields: " + ", ".join(missing)
                )
            basin_ids = np.asarray(archive["basin_id"]).astype(str)
            seeds = np.asarray(archive["seed"])
            probabilities = np.asarray(
                archive["initial_probabilities"], dtype=np.float64
            )
            states = np.asarray(archive["initial_states"], dtype=np.float64)
            covariances = np.asarray(
                archive["initial_covariances"], dtype=np.float64
            )
            probability_axis = np.asarray(
                archive["initial_probability_axis_order"]
            ).astype(str)
            state_axis = np.asarray(archive["initial_state_axis_order"]).astype(str)
            covariance_axis = np.asarray(
                archive["initial_covariance_axis_order"]
            ).astype(str)
    except ValueError:
        raise
    except Exception as error:
        raise ValueError("initial moment manifest is unreadable") from error

    task_count = len(tasks)
    expected_basin_ids = tasks["basin_id"].to_numpy(dtype=str)
    expected_seeds = tasks["seed"].to_numpy(dtype=np.int64)
    integer_seeds = seeds.astype(np.int64)
    if (
        basin_ids.shape != (task_count,)
        or seeds.shape != (task_count,)
        or not np.array_equal(basin_ids, expected_basin_ids)
        or not np.array_equal(integer_seeds, expected_seeds)
        or not np.array_equal(seeds, integer_seeds)
    ):
        raise ValueError("initial moment manifest task identities do not match tasks")
    candidate_count = 3
    state_count = len(FULL_STATE_NAMES)
    if probabilities.shape != (task_count, candidate_count):
        raise ValueError(
            "initial_probabilities must have shape "
            f"{(task_count, candidate_count)}"
        )
    if states.shape != (task_count, candidate_count, state_count):
        raise ValueError(
            "initial_states must have shape "
            f"{(task_count, candidate_count, state_count)}"
        )
    if covariances.shape != (
        task_count,
        candidate_count,
        state_count,
        state_count,
    ):
        raise ValueError(
            "initial_covariances must have shape "
            f"{(task_count, candidate_count, state_count, state_count)}"
        )
    if not np.all(np.isfinite(probabilities)) or np.any(probabilities < 0.0):
        raise ValueError("initial probabilities must be finite and nonnegative")
    if not np.allclose(
        probabilities.sum(axis=1), 1.0, rtol=0.0, atol=1e-12
    ):
        raise ValueError("initial probabilities must sum to one")
    if not np.all(np.isfinite(states)) or not np.all(np.isfinite(covariances)):
        raise ValueError("initial states and covariances must be finite")
    if not np.allclose(
        covariances,
        np.swapaxes(covariances, -1, -2),
        rtol=0.0,
        atol=1e-12,
    ):
        raise ValueError("initial covariances must be symmetric")
    if not np.array_equal(probability_axis, ["task", "candidate"]):
        raise ValueError("initial probability axis order changed")
    if not np.array_equal(state_axis, ["task", "candidate", "state"]):
        raise ValueError("initial state axis order changed")
    if not np.array_equal(
        covariance_axis,
        ["task", "candidate", "state_row", "state_column"],
    ):
        raise ValueError("initial covariance axis order changed")
    return path, observed_hash, task_count


def _verify_raw_input_manifest(
    root: Path,
    inputs: Mapping,
) -> tuple[str, int]:
    manifest_path = _registered_file(
        root,
        inputs.get("raw_input_manifest"),
        "raw-input manifest",
    )
    manifest_hash = _verify_file_hash(
        manifest_path,
        inputs.get("raw_input_manifest_sha256"),
        "raw-input manifest",
    )
    manifest = pd.read_csv(manifest_path, keep_default_na=False)
    required = {"relative_path", "bytes", "sha256"}
    missing = sorted(required.difference(manifest.columns))
    if missing:
        raise ValueError(
            "raw-input manifest lacks required columns: " + ", ".join(missing)
        )
    if manifest.empty:
        raise ValueError("raw-input manifest must contain at least one file")
    if manifest["relative_path"].duplicated().any():
        raise ValueError("raw-input manifest contains duplicate paths")
    for row in manifest.itertuples(index=False):
        path = _registered_file(root, row.relative_path, "raw input")
        try:
            expected_bytes = int(row.bytes)
        except (TypeError, ValueError) as error:
            raise ValueError(
                f"raw-input manifest has invalid byte count for {row.relative_path}"
            ) from error
        try:
            if float(row.bytes) != expected_bytes or expected_bytes < 0:
                raise ValueError
        except (TypeError, ValueError) as error:
            raise ValueError(
                f"raw-input manifest has invalid byte count for {row.relative_path}"
            ) from error
        observed_bytes = path.stat().st_size
        if observed_bytes != expected_bytes:
            raise ValueError(
                f"raw input byte count changed for {row.relative_path}: "
                f"expected {expected_bytes}, observed {observed_bytes}"
            )
        observed_hash = sha256_file(path)
        if observed_hash != str(row.sha256):
            raise ValueError(
                f"raw input SHA-256 changed for {row.relative_path}: "
                f"expected {row.sha256}, observed {observed_hash}"
            )
    return manifest_hash, int(len(manifest))


def _load_parameter_rows(
    root: Path,
    inputs: Mapping,
    selected_basins: Sequence[str],
) -> dict[str, dict]:
    parameter_path = _registered_file(root, inputs.get("parameter_table"), "parameter table")
    g1_path = _registered_file(root, inputs.get("g1_precheck_table"), "G1 precheck table")
    parameters = pd.read_csv(parameter_path, dtype={"basin_id": str})
    g1 = pd.read_csv(g1_path, dtype={"basin_id": str})
    for name, frame in (("parameter", parameters), ("G1 precheck", g1)):
        if "basin_id" not in frame:
            raise ValueError(f"{name} table lacks basin_id")
        frame["basin_id"] = [_normalize_basin_id(value) for value in frame["basin_id"]]
        if frame["basin_id"].duplicated().any():
            raise ValueError(f"{name} table contains duplicate basin identifiers")
    required_parameter = [f"p_{key}" for key in PARAM_KEYS]
    required_parameter += [f"state_{name}" for name in HYDRO_STATE_NAMES]
    missing_parameter = [name for name in required_parameter if name not in parameters]
    if missing_parameter:
        raise ValueError(
            "parameter table lacks required columns: " + ", ".join(missing_parameter)
        )
    if "sigma_obs" not in g1:
        raise ValueError("G1 precheck table lacks sigma_obs")
    selected = list(dict.fromkeys(selected_basins))
    parameter_subset = parameters[parameters["basin_id"].isin(selected)].copy()
    g1_subset = g1[g1["basin_id"].isin(selected)][["basin_id", "sigma_obs"]].copy()
    if set(parameter_subset["basin_id"]) != set(selected):
        raise ValueError("parameter table lacks one or more selected basins")
    if set(g1_subset["basin_id"]) != set(selected):
        raise ValueError("G1 precheck table lacks one or more selected basins")
    merged = parameter_subset.merge(g1_subset, on="basin_id", validate="one_to_one")
    numeric_columns = required_parameter + ["sigma_obs"]
    for column in numeric_columns:
        merged[column] = pd.to_numeric(merged[column], errors="coerce")
    if merged[numeric_columns].isna().any().any() or not all(
        math.isfinite(float(value))
        for value in merged[numeric_columns].to_numpy().ravel()
    ):
        raise ValueError("selected parameter or G1 values must be finite")
    if (merged["sigma_obs"] <= 0).any():
        raise ValueError("selected sigma_obs values must be positive")
    return {
        str(row["basin_id"]): dict(row)
        for row in merged.to_dict("records")
    }


def verify_parameter_path_mechanism(
    repo_root: str | Path,
    config_path: str | Path,
    expected_config_sha256: str,
) -> VerifiedMechanismRun:
    root = Path(repo_root).resolve()
    configuration = Path(config_path).resolve()
    if not configuration.is_file():
        raise FileNotFoundError(f"configuration is missing: {configuration}")
    try:
        configuration.relative_to(root)
    except ValueError as error:
        raise ValueError("configuration path must be inside the repository root") from error
    observed_config_hash = sha256_file(configuration)
    if observed_config_hash != str(expected_config_sha256):
        raise ValueError(
            "configuration SHA-256 changed: "
            f"expected {expected_config_sha256}, observed {observed_config_hash}"
        )
    config = json.loads(configuration.read_text(encoding="utf-8"))
    if not isinstance(config, Mapping):
        raise ValueError("configuration root must be a JSON object")
    experiment_id = config.get("experiment_id")
    if not isinstance(experiment_id, str) or not experiment_id.strip():
        raise ValueError("experiment_id must be a nonempty string")
    if config.get("configuration_status") != CONFIGURATION_STATUS:
        raise ValueError(f"configuration_status must be {CONFIGURATION_STATUS}")
    runtime_contract = _verify_runtime_contract(config)
    _verify_filter_and_arms(config)
    implementation_hashes = _verify_implementation(root, config)
    inputs = config.get("inputs")
    outputs = config.get("outputs")
    if not isinstance(inputs, Mapping) or not isinstance(outputs, Mapping):
        raise ValueError("inputs and outputs must be mappings")
    parameter_path = _registered_file(
        root,
        inputs.get("parameter_table"),
        "parameter table",
    )
    parameter_hash = _verify_file_hash(
        parameter_path,
        inputs.get("parameter_table_sha256"),
        "parameter table",
    )
    g1_path = _registered_file(
        root,
        inputs.get("g1_precheck_table"),
        "G1 precheck table",
    )
    g1_hash = _verify_file_hash(
        g1_path,
        inputs.get("g1_precheck_table_sha256"),
        "G1 precheck table",
    )
    raw_manifest_hash, raw_manifest_rows = _verify_raw_input_manifest(root, inputs)
    tasks, task_path, task_hash = _verify_tasks(root, inputs)
    _, initial_manifest_hash, initial_manifest_rows = _verify_initial_moment_manifest(
        root,
        inputs,
        tasks,
    )
    data_root = _relative_path(root, inputs.get("data_root"), "data root").resolve()
    if not data_root.is_dir():
        raise FileNotFoundError(f"data root directory is missing: {data_root}")
    parameter_rows = _load_parameter_rows(root, inputs, list(tasks["basin_id"]))
    output_root = _verify_output_root(root, outputs, tasks)
    return VerifiedMechanismRun(
        configuration=json.loads(json.dumps(config)),
        config_path=configuration,
        config_sha256=observed_config_hash,
        task_table=tasks,
        task_table_path=task_path,
        task_table_sha256=task_hash,
        parameter_rows=parameter_rows,
        data_root=data_root,
        output_root=output_root,
        implementation_hashes=implementation_hashes,
        input_hashes={
            "parameter_table_sha256": parameter_hash,
            "g1_precheck_table_sha256": g1_hash,
            "raw_input_manifest_sha256": raw_manifest_hash,
            "raw_input_manifest_rows": raw_manifest_rows,
            "initial_moment_manifest_sha256": initial_manifest_hash,
            "initial_moment_manifest_rows": initial_manifest_rows,
        },
        runtime_contract=runtime_contract,
    )


def _build_work(verified: VerifiedMechanismRun) -> list[tuple]:
    config = verified.configuration
    filter_config = config["filter"]
    work: list[tuple] = []
    for arm in config["arms"]:
        probability_directory = verified.output_root / "arms" / arm["arm_id"] / "probs"
        for task in verified.task_table.to_dict("records"):
            work.append(
                (
                    str(task["basin_id"]),
                    int(task["seed"]),
                    str(verified.data_root),
                    dict(verified.parameter_rows[str(task["basin_id"])]),
                    float(filter_config["q_scale"]),
                    str(filter_config["q_structure"]),
                    str(filter_config["q_mode"]),
                    float(filter_config["q_state_multiplier"]),
                    float(filter_config["observation_variance_multiplier"]),
                    str(arm["interaction_mode"]),
                    str(arm["parameter_state_mapping"]),
                    str(probability_directory),
                    str(arm["arm_id"]),
                )
            )
    return work


def _write_outputs(verified: VerifiedMechanismRun, execution) -> dict:
    records = pd.DataFrame(execution.records)
    for arm_id in ("C", "P"):
        arm_records = records[records["arm_id"] == arm_id].copy()
        arm_records.to_csv(
            verified.output_root / "arms" / arm_id / "tasks.csv",
            index=False,
        )
    counts = {
        status: int(count)
        for status, count in records["run_status"].value_counts().items()
    }
    summary = {
        "experiment_id": verified.configuration["experiment_id"],
        "configuration_status": verified.configuration["configuration_status"],
        "config_path": str(verified.config_path),
        "config_sha256": verified.config_sha256,
        "task_table_path": str(verified.task_table_path),
        "task_table_sha256": verified.task_table_sha256,
        "implementation_hashes": verified.implementation_hashes,
        "runtime": verified.runtime_contract,
        "registered_input_hashes": verified.input_hashes,
        "execution_status": execution.execution_status,
        "scientific_aggregation_status": (
            "ready_for_independent_mechanism_verification"
            if execution.execution_status == "complete"
            else "not_evaluated_incomplete_execution"
        ),
        "n_source_tasks": 10,
        "n_arms": 2,
        "n_tasks_planned": int(execution.n_planned),
        "n_submitted": int(execution.n_submitted),
        "run_status_counts": counts,
        "n_cancelled_before_start": int(execution.n_cancelled_before_start),
        "n_not_submitted_after_failure": int(
            execution.n_not_submitted_after_failure
        ),
        "n_completed_after_stop": int(execution.n_completed_after_stop),
        "first_failure": execution.first_failure,
        "filter": {key: verified.configuration["filter"][key] for key in EXPECTED_FILTER},
        "arms": verified.configuration["arms"],
    }
    with (verified.output_root / "runner_summary.json").open(
        "x", encoding="utf-8"
    ) as handle:
        json.dump(summary, handle, indent=2, sort_keys=True)
        handle.write("\n")
    return summary


def run_parameter_path_mechanism(
    config_path: str | Path,
    expected_config_sha256: str,
    workers: int,
) -> dict:
    if isinstance(workers, bool) or not isinstance(workers, int) or workers <= 0:
        raise ValueError("workers must be a positive integer")
    verified = verify_parameter_path_mechanism(
        _REPO_ROOT,
        config_path,
        expected_config_sha256,
    )
    work = _build_work(verified)
    if len(work) != 20:
        raise RuntimeError("internal work construction must produce exactly 20 tasks")

    verified.output_root.mkdir(parents=True, exist_ok=False)
    arms_root = verified.output_root / "arms"
    arms_root.mkdir(exist_ok=False)
    for arm_id in ("C", "P"):
        arm_root = arms_root / arm_id
        arm_root.mkdir(exist_ok=False)
        (arm_root / "probs").mkdir(exist_ok=False)

    execution = execute_fail_fast(
        work=work,
        worker=_run_one,
        task_key=lambda item: {
            "basin_id": item[0],
            "seed": item[1],
            "arm_id": item[-1],
        },
        max_workers=workers,
    )
    return _write_outputs(verified, execution)


def _parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True)
    parser.add_argument("--expected-config-sha256", required=True)
    parser.add_argument("--workers", type=int, default=4)
    return parser.parse_args(argv)


def main(argv=None) -> int:
    arguments = _parse_args(argv)
    try:
        summary = run_parameter_path_mechanism(
            arguments.config,
            arguments.expected_config_sha256,
            arguments.workers,
        )
    except Exception as error:  # noqa: BLE001 - the executable must stop cleanly
        print(f"STOP: {type(error).__name__}: {error}", file=sys.stderr)
        return 1
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0 if summary["execution_status"] == "complete" else 1


if __name__ == "__main__":
    raise SystemExit(main())
