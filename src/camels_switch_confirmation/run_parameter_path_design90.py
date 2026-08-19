"""Registered 90-basin C/P path-postcollapse design runner.

This module deliberately leaves the completed 03B mechanism runner untouched.
It reuses that runner's frozen numerical and integrity helpers while replacing
only the registered sample-size contract: 90 basins, design seeds 0 and 1,
two arms, and 360 total tasks.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Mapping, Sequence
from pathlib import Path

import pandas as pd

from camels_switch_confirmation import run_parameter_path_mechanism as base
from camels_switch_confirmation.batch_control import execute_fail_fast
from camels_switch_confirmation.g2_switch_confirmation import _run_one


_REPO_ROOT = Path(__file__).resolve().parents[2]

CONFIGURATION_STATUS = "design90_exploratory_design_seeds_not_validation"
SOURCE_TASK_COUNT = 180
BASIN_COUNT = 90
ARM_COUNT = 2
PLANNED_TASK_COUNT = SOURCE_TASK_COUNT * ARM_COUNT
DESIGN_SEEDS = (0, 1)
DESIGN_REQUIRED_IMPLEMENTATION_ROLES = frozenset(
    {
        "design90_runner",
        "design90_runner_tests",
        "design90_verifier",
        "design90_verifier_tests",
        "design90_registration",
        "design90_registration_tests",
    }
)
COMPLETED_MECHANISM_ROOT = (
    Path("results")
    / "23_camels_switch_confirmation"
    / "camels_parfc_transition_path_03b_mechanism10_s01_20260811_local"
)


def _normalize_basin_list(values: Sequence[object]) -> list[str]:
    basins = [base._normalize_basin_id(value) for value in values]
    if len(basins) != BASIN_COUNT or len(set(basins)) != BASIN_COUNT:
        raise ValueError("Design90 basin list must contain exactly 90 unique basins")
    return basins


def validate_design90_task_frame(
    tasks: pd.DataFrame,
    basin_ids: Sequence[object],
) -> pd.DataFrame:
    """Validate the exact ordered 90-basin by two-seed source-task cross product."""
    if not isinstance(tasks, pd.DataFrame):
        raise TypeError("tasks must be a pandas DataFrame")
    missing = sorted(base.TASK_COLUMNS.difference(tasks.columns))
    if missing:
        raise ValueError("task table lacks required columns: " + ", ".join(missing))
    basins = _normalize_basin_list(basin_ids)
    result = tasks.copy()
    result["basin_id"] = [base._normalize_basin_id(value) for value in result["basin_id"]]
    numeric_seed = pd.to_numeric(result["seed"], errors="coerce")
    if numeric_seed.isna().any() or any(
        float(value) != int(value) for value in numeric_seed
    ):
        raise ValueError("task seeds must be integers")
    result["seed"] = numeric_seed.astype(int)
    identities = list(zip(result["basin_id"], result["seed"]))
    if len(result) != SOURCE_TASK_COUNT:
        raise ValueError("task table must contain exactly 180 source tasks")
    if len(set(identities)) != SOURCE_TASK_COUNT:
        raise ValueError("task table must contain 180 unique basin-seed identities")
    if set(result["seed"]) != set(DESIGN_SEEDS):
        raise ValueError("design task seeds must be exactly 0 and 1")
    if not (result["arm_id"].astype(str) == "C").all():
        raise ValueError("every registered source task must use arm C")
    expected_identities = [
        (basin_id, seed) for basin_id in basins for seed in DESIGN_SEEDS
    ]
    if identities != expected_identities:
        raise ValueError(
            "task identities or order must equal basin-list order crossed with seeds 0,1"
        )
    counts = result.groupby("basin_id", sort=False)["seed"].agg(list).to_dict()
    if any(values != [0, 1] for values in counts.values()):
        raise ValueError("each Design90 basin must occur once for each design seed")
    return result.reset_index(drop=True)


def _load_basin_list(
    root: Path,
    config: Mapping,
) -> tuple[list[str], Path, str]:
    selection = config.get("design_selection")
    if not isinstance(selection, Mapping) or selection.get("basin_count") != BASIN_COUNT:
        raise ValueError("design_selection must register exactly 90 basins")
    path = base._registered_file(
        root,
        selection.get("basin_list"),
        "Design90 basin list",
    )
    observed_hash = base._verify_file_hash(
        path,
        selection.get("basin_list_sha256"),
        "Design90 basin list",
    )
    frame = pd.read_csv(path, dtype={"basin_id": str}, keep_default_na=False)
    if "basin_id" not in frame:
        raise ValueError("Design90 basin list lacks basin_id")
    return _normalize_basin_list(frame["basin_id"].tolist()), path, observed_hash


def _verify_tasks(
    root: Path,
    inputs: Mapping,
    basin_ids: Sequence[str],
) -> tuple[pd.DataFrame, Path, str]:
    task_path = base._registered_file(root, inputs.get("task_table"), "task table")
    observed_hash = base.sha256_file(task_path)
    if observed_hash != str(inputs.get("task_table_sha256")):
        raise ValueError("task table SHA-256 changed")
    tasks = pd.read_csv(
        task_path,
        dtype={"basin_id": str, "arm_id": str},
        keep_default_na=False,
    )
    tasks = validate_design90_task_frame(tasks, basin_ids)
    for row in tasks.itertuples(index=False):
        source = base._registered_file(
            root,
            row.source_probability_path,
            f"source probability file {row.basin_id} seed {row.seed}",
        )
        try:
            expected_bytes = int(row.source_probability_bytes)
            if float(row.source_probability_bytes) != expected_bytes:
                raise ValueError
        except (TypeError, ValueError) as error:
            raise ValueError("source probability byte count must be an integer") from error
        if source.stat().st_size != expected_bytes:
            raise ValueError(
                f"source probability byte count changed for {row.basin_id} seed {row.seed}"
            )
        if base.sha256_file(source) != str(row.source_probability_sha256):
            raise ValueError(
                f"source probability SHA-256 changed for {row.basin_id} seed {row.seed}"
            )
        base._verify_source_probability_content(source, row)
    return tasks, task_path, observed_hash


def _verify_implementation(root: Path, config: Mapping) -> dict[str, str]:
    implementation = config.get("implementation")
    if not isinstance(implementation, Mapping):
        raise ValueError("implementation must be a mapping")
    missing = sorted(DESIGN_REQUIRED_IMPLEMENTATION_ROLES.difference(implementation))
    if missing:
        raise ValueError(
            "Design90 implementation mapping lacks roles: " + ", ".join(missing)
        )
    return base._verify_implementation(root, config)


def _verify_authorization_boundary(config: Mapping) -> None:
    boundary = config.get("authorization_boundary")
    if not isinstance(boundary, Mapping):
        raise ValueError("authorization_boundary must be a mapping")
    expected = {
        "design_seeds": [0, 1],
        "reserved_validation_seeds_authorized": False,
        "full_531_basin_run_authorized": False,
        "configuration_freeze_version_02_authorized": False,
        "requires_separate_360_task_execution_go": True,
    }
    for name, value in expected.items():
        if boundary.get(name) != value:
            raise ValueError(f"authorization boundary changed for {name}")


def _verify_parent_mechanism(root: Path, config: Mapping) -> dict[str, str]:
    parent = config.get("parent_mechanism")
    if not isinstance(parent, Mapping):
        raise ValueError("parent_mechanism must be a mapping")
    if parent.get("mechanism_gate_status") != "GO":
        raise ValueError("parent mechanism gate must be GO")
    evidence = base._registered_file(
        root,
        parent.get("evidence_path"),
        "parent mechanism evidence",
    )
    evidence_hash = base._verify_file_hash(
        evidence,
        parent.get("evidence_sha256"),
        "parent mechanism evidence",
    )
    summary = base._registered_file(
        root,
        parent.get("verification_summary_path"),
        "parent mechanism verification summary",
    )
    summary_hash = base._verify_file_hash(
        summary,
        parent.get("verification_summary_sha256"),
        "parent mechanism verification summary",
    )
    values = json.loads(summary.read_text(encoding="utf-8"))
    if (
        values.get("verification_status") != "passed"
        or values.get("mechanism_gate_status") != "GO"
        or values.get("task_count") != 20
    ):
        raise ValueError("parent mechanism verification is not a completed GO")
    return {
        "parent_mechanism_evidence_sha256": evidence_hash,
        "parent_mechanism_verification_summary_sha256": summary_hash,
    }


def verify_parameter_path_design90(
    repo_root: str | Path,
    config_path: str | Path,
    expected_config_sha256: str,
) -> base.VerifiedMechanismRun:
    """Verify a frozen Design90 configuration without creating its output."""
    root = Path(repo_root).resolve()
    configuration = Path(config_path)
    if not configuration.is_absolute():
        configuration = root / configuration
    configuration = configuration.resolve()
    if not configuration.is_file():
        raise FileNotFoundError(f"configuration is missing: {configuration}")
    try:
        configuration.relative_to(root)
    except ValueError as error:
        raise ValueError("configuration path must be inside the repository root") from error
    observed_config_hash = base.sha256_file(configuration)
    if observed_config_hash != str(expected_config_sha256):
        raise ValueError(
            "configuration SHA-256 changed: "
            f"expected {expected_config_sha256}, observed {observed_config_hash}"
        )
    config = json.loads(configuration.read_text(encoding="utf-8"))
    if not isinstance(config, Mapping):
        raise ValueError("configuration root must be a JSON object")
    if config.get("configuration_status") != CONFIGURATION_STATUS:
        raise ValueError(f"configuration_status must be {CONFIGURATION_STATUS}")
    experiment_id = config.get("experiment_id")
    if experiment_id != "CAMELS_PARFC_TRANSITION_PATH_03B_DESIGN90":
        raise ValueError("Design90 experiment_id changed")
    _verify_authorization_boundary(config)
    runtime_contract = base._verify_runtime_contract(config)
    base._verify_filter_and_arms(config)
    implementation_hashes = _verify_implementation(root, config)
    parent_hashes = _verify_parent_mechanism(root, config)
    inputs = config.get("inputs")
    outputs = config.get("outputs")
    if not isinstance(inputs, Mapping) or not isinstance(outputs, Mapping):
        raise ValueError("inputs and outputs must be mappings")
    basin_ids, _, basin_list_hash = _load_basin_list(root, config)
    tasks, task_path, task_hash = _verify_tasks(root, inputs, basin_ids)
    _, initial_manifest_hash, initial_manifest_rows = base._verify_initial_moment_manifest(
        root,
        inputs,
        tasks,
    )
    parameter_path = base._registered_file(
        root, inputs.get("parameter_table"), "parameter table"
    )
    parameter_hash = base._verify_file_hash(
        parameter_path,
        inputs.get("parameter_table_sha256"),
        "parameter table",
    )
    g1_path = base._registered_file(root, inputs.get("g1_precheck_table"), "G1 table")
    g1_hash = base._verify_file_hash(
        g1_path,
        inputs.get("g1_precheck_table_sha256"),
        "G1 table",
    )
    raw_manifest_hash, raw_manifest_rows = base._verify_raw_input_manifest(root, inputs)
    data_root = base._relative_path(root, inputs.get("data_root"), "data root").resolve()
    if not data_root.is_dir():
        raise FileNotFoundError(f"data root directory is missing: {data_root}")
    parameter_rows = base._load_parameter_rows(root, inputs, basin_ids)
    output_root = base._verify_output_root(root, outputs, tasks)
    completed_mechanism_root = (root / COMPLETED_MECHANISM_ROOT).resolve()
    if output_root == completed_mechanism_root or base._is_within(
        output_root, completed_mechanism_root
    ):
        raise ValueError("Design90 output must not enter the completed mechanism root")
    return base.VerifiedMechanismRun(
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
            "basin_list_sha256": basin_list_hash,
            **parent_hashes,
        },
        runtime_contract=runtime_contract,
    )


def _build_work(verified: base.VerifiedMechanismRun) -> list[tuple]:
    return base._build_work(verified)


def _write_outputs(verified: base.VerifiedMechanismRun, execution) -> dict:
    records = pd.DataFrame(execution.records)
    for arm_id in ("C", "P"):
        records[records["arm_id"] == arm_id].copy().to_csv(
            verified.output_root / "arms" / arm_id / "tasks.csv",
            index=False,
        )
    counts = {
        status: int(count)
        for status, count in records["run_status"].value_counts().items()
    }
    source_count = int(len(verified.task_table))
    arm_count = int(len(verified.configuration["arms"]))
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
            "ready_for_independent_design90_verification"
            if execution.execution_status == "complete"
            else "not_evaluated_incomplete_execution"
        ),
        "n_source_tasks": source_count,
        "n_arms": arm_count,
        "n_tasks_planned": int(execution.n_planned),
        "n_submitted": int(execution.n_submitted),
        "run_status_counts": counts,
        "n_cancelled_before_start": int(execution.n_cancelled_before_start),
        "n_not_submitted_after_failure": int(execution.n_not_submitted_after_failure),
        "n_completed_after_stop": int(execution.n_completed_after_stop),
        "first_failure": execution.first_failure,
        "filter": dict(verified.configuration["filter"]),
        "arms": verified.configuration["arms"],
    }
    with (verified.output_root / "runner_summary.json").open(
        "x", encoding="utf-8"
    ) as handle:
        json.dump(summary, handle, indent=2, sort_keys=True)
        handle.write("\n")
    return summary


def run_parameter_path_design90(
    config_path: str | Path,
    expected_config_sha256: str,
    workers: int,
) -> dict:
    if isinstance(workers, bool) or not isinstance(workers, int) or workers <= 0:
        raise ValueError("workers must be a positive integer")
    verified = verify_parameter_path_design90(
        _REPO_ROOT,
        config_path,
        expected_config_sha256,
    )
    work = _build_work(verified)
    if len(work) != PLANNED_TASK_COUNT:
        raise RuntimeError("internal work construction must produce exactly 360 tasks")
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
        summary = run_parameter_path_design90(
            arguments.config,
            arguments.expected_config_sha256,
            arguments.workers,
        )
    except Exception as error:  # noqa: BLE001 - executable must stop cleanly
        print(f"STOP: {type(error).__name__}: {error}", file=sys.stderr)
        return 1
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
