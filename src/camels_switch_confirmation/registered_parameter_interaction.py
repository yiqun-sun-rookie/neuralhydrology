"""Registered exploratory runner for the CAMELS parFC interaction diagnostic."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Mapping, Sequence

import pandas as pd

from camels_switch_confirmation.batch_control import execute_fail_fast
from camels_switch_confirmation.g2_switch_confirmation import (
    PARAM_KEYS,
    STATE_NAMES,
    _run_one,
    classify_basin_verdict,
)
from camels_switch_confirmation.run_integrity import (
    verify_parameter_run_config,
)


_REPO_ROOT = Path(__file__).resolve().parents[2]


def prepare_output_root(path: str | Path) -> Path:
    """Create one new output root and refuse any pre-existing target."""
    output = Path(path).resolve()
    if output.exists():
        raise FileExistsError(f"output root already exists: {output}")
    output.mkdir(parents=True, exist_ok=False)
    return output


def _write_csv_new(frame: pd.DataFrame, path: Path) -> None:
    if path.exists():
        raise FileExistsError(f"output table already exists: {path}")
    frame.to_csv(path, index=False)


def write_arm_evidence(
    arm_directory: str | Path,
    execution,
    g1_frame: pd.DataFrame,
    selected_seeds: Sequence[int],
    metadata: Mapping,
) -> dict:
    """Write task and basin evidence, including a valid zero-success record."""
    arm_path = Path(arm_directory)
    records = list(execution.records)
    if records:
        events = pd.DataFrame(records)
        sort_columns = [name for name in ("task_index", "basin_id", "seed")
                        if name in events.columns]
        if sort_columns:
            events = events.sort_values(sort_columns).reset_index(drop=True)
    else:
        events = pd.DataFrame(
            columns=["task_index", "basin_id", "seed", "run_status",
                     "error_message", "arm_id"]
        )
    _write_csv_new(events, arm_path / "g2_events.csv")

    if "run_status" in events:
        successful = events[events["run_status"] == "success"].copy()
        failed_count = int((events["run_status"] == "failed").sum())
    else:
        successful = events.iloc[0:0].copy()
        failed_count = 0

    verdict_rows = []
    if not successful.empty and {"n_events", "n_events_passed"}.issubset(
        successful.columns
    ):
        for basin_id, group in successful.groupby("basin_id"):
            event_total = int(group["n_events"].sum())
            event_passed = int(group["n_events_passed"].sum())
            verdict_rows.append(
                {
                    "basin_id": str(basin_id),
                    "events_total": event_total,
                    "events_passed": event_passed,
                    "verdict": classify_basin_verdict(event_total, event_passed),
                }
            )
    verdict_columns = ["basin_id", "events_total", "events_passed", "verdict"]
    verdicts = pd.DataFrame(verdict_rows, columns=verdict_columns)
    g1_columns = [
        "basin_id",
        "predicted_identifiable",
        "r_min",
        "nse_calibration_table",
    ]
    g1_subset = g1_frame[g1_columns].copy()
    g1_subset["basin_id"] = g1_subset["basin_id"].astype(str).str.zfill(8)
    if verdicts.empty:
        for name in g1_columns[1:]:
            verdicts[name] = pd.Series(dtype=g1_subset[name].dtype)
    else:
        verdicts["basin_id"] = verdicts["basin_id"].astype(str).str.zfill(8)
        verdicts = verdicts.merge(
            g1_subset,
            on="basin_id",
            how="left",
            validate="one_to_one",
        )
    _write_csv_new(verdicts, arm_path / "g2_basin_verdicts.csv")

    complete = execution.execution_status == "complete"
    aggregation_status = (
        "evaluated_complete_design"
        if complete
        else "not_evaluated_incomplete_execution"
    )
    basin_status = (
        "evaluated_two_design_seeds"
        if complete and tuple(int(seed) for seed in selected_seeds) == (0, 1)
        else "not_evaluated_incomplete_execution"
    )
    summary = {
        **dict(metadata),
        "execution_status": execution.execution_status,
        "scientific_aggregation_status": aggregation_status,
        "basin_verdict_status": basin_status,
        "seeds": [int(seed) for seed in selected_seeds],
        "n_tasks": int(execution.n_planned),
        "n_submitted": int(execution.n_submitted),
        "n_success": int(len(successful)),
        "n_failed": failed_count,
        "n_cancelled_before_start": int(execution.n_cancelled_before_start),
        "n_not_submitted_after_failure": int(
            execution.n_not_submitted_after_failure
        ),
        "n_completed_after_stop": int(execution.n_completed_after_stop),
        "first_failure": execution.first_failure,
        "n_basins_with_any_success": int(len(verdicts)),
    }
    summary_path = arm_path / "g2_summary.json"
    with summary_path.open("x", encoding="utf-8") as handle:
        json.dump(summary, handle, indent=2, sort_keys=True)
        handle.write("\n")
    return summary


def _load_registered_rows(verified, config: Mapping) -> tuple[list[dict], pd.DataFrame]:
    """Join the exact registered basins to parameters and observation error."""
    repository_root = verified.repo_root
    inputs = config["inputs"]
    parameter_table = pd.read_csv(
        repository_root / inputs["parameter_table"],
        dtype={"basin_id": str},
    )
    precheck_table = pd.read_csv(
        repository_root / inputs["g1_precheck_table"],
        dtype={"basin_id": str},
    )
    for frame in (parameter_table, precheck_table):
        if "basin_id" not in frame:
            raise ValueError("registered table lacks basin_id")
        frame["basin_id"] = frame["basin_id"].str.zfill(8)
        if frame["basin_id"].duplicated().any():
            raise ValueError("registered table contains duplicate basin identifiers")
    selection = pd.DataFrame({"basin_id": list(verified.basin_ids)})
    rows = selection.merge(
        parameter_table,
        on="basin_id",
        how="left",
        validate="one_to_one",
    ).merge(
        precheck_table[["basin_id", "sigma_obs"]],
        on="basin_id",
        how="left",
        validate="one_to_one",
    )
    required = [f"p_{key}" for key in PARAM_KEYS]
    required += [f"state_{name}" for name in STATE_NAMES]
    required += ["sigma_obs"]
    if any(name not in rows for name in required):
        missing = [name for name in required if name not in rows]
        raise ValueError("registered parameter rows lack columns: " + ", ".join(missing))
    if rows[required].isna().any().any():
        raise ValueError("selected basin inputs contain missing values")
    g1_required = [
        "basin_id",
        "predicted_identifiable",
        "r_min",
        "nse_calibration_table",
    ]
    if any(name not in precheck_table for name in g1_required):
        missing = [name for name in g1_required if name not in precheck_table]
        raise ValueError("registered precheck table lacks columns: " + ", ".join(missing))
    g1 = selection.merge(
        precheck_table[g1_required],
        on="basin_id",
        how="left",
        validate="one_to_one",
    )
    return rows.to_dict("records"), g1


def _arm_work(
    rows: Sequence[Mapping],
    seeds: Sequence[int],
    data_root: Path,
    filter_config: Mapping,
    arm: Mapping,
    probability_directory: Path,
) -> list[tuple]:
    work = []
    for row_value in rows:
        row = dict(row_value)
        for seed in seeds:
            work.append(
                (
                    str(row["basin_id"]),
                    int(seed),
                    str(data_root),
                    row,
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


def _write_root_summary(output: Path, summary: Mapping) -> None:
    with (output / "runner_summary.json").open("x", encoding="utf-8") as handle:
        json.dump(dict(summary), handle, indent=2, sort_keys=True)
        handle.write("\n")


def run_registered_parameter_design(
    config_path: str | Path,
    expected_config_sha256: str,
    workers: int,
) -> dict:
    """Run the registered three-arm design, stopping before later arms on failure."""
    if isinstance(workers, bool) or not isinstance(workers, int) or workers <= 0:
        raise ValueError("workers must be a positive integer")
    configuration = Path(config_path).resolve()
    verified = verify_parameter_run_config(
        _REPO_ROOT,
        configuration,
        expected_config_sha256,
    )
    config = verified.configuration
    rows, g1_frame = _load_registered_rows(verified, config)
    seeds = tuple(int(seed) for seed in config["seeds"]["design"])
    filter_config = config["filter"]

    output = prepare_output_root(verified.output_root)
    arm_summaries = []
    overall_status = "complete"
    failure = None
    try:
        arms_root = output / "arms"
        arms_root.mkdir(exist_ok=False)
        for arm in verified.arms:
            arm_directory = arms_root / str(arm["arm_id"])
            arm_directory.mkdir(exist_ok=False)
            probability_directory = arm_directory / "probs"
            probability_directory.mkdir(exist_ok=False)
            work = _arm_work(
                rows,
                seeds,
                verified.data_root,
                filter_config,
                arm,
                probability_directory,
            )
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
            arm_summary = write_arm_evidence(
                arm_directory=arm_directory,
                execution=execution,
                g1_frame=g1_frame,
                selected_seeds=seeds,
                metadata={
                    "experiment_id": verified.experiment_id,
                    "configuration_status": verified.configuration_status,
                    "config_sha256": verified.config_sha256,
                    "arm_id": arm["arm_id"],
                    "state_interaction_mode": arm["interaction_mode"],
                    "parameter_state_mapping": arm["parameter_state_mapping"],
                    "q_scale": float(filter_config["q_scale"]),
                    "q_structure": filter_config["q_structure"],
                    "q_mode": filter_config["q_mode"],
                    "q_state_multiplier": float(filter_config["q_state_multiplier"]),
                    "filter_r_multiplier": float(
                        filter_config["observation_variance_multiplier"]
                    ),
                },
            )
            arm_summaries.append(arm_summary)
            if execution.execution_status != "complete":
                overall_status = "failed_early"
                break
    except Exception as error:  # noqa: BLE001 - preserve root-level failure evidence
        overall_status = "failed_early"
        failure = {
            "error_type": type(error).__name__,
            "error_message": f"{type(error).__name__}: {error}",
        }

    root_summary = {
        "experiment_id": verified.experiment_id,
        "configuration_status": verified.configuration_status,
        "config_path": str(verified.config_path),
        "config_sha256": verified.config_sha256,
        "execution_status": overall_status,
        "scientific_aggregation_status": (
            "ready_for_independent_verification"
            if overall_status == "complete"
            else "not_evaluated_incomplete_execution"
        ),
        "n_basins": len(verified.basin_ids),
        "seeds": list(seeds),
        "n_arms_planned": len(verified.arms),
        "n_arms_started": len(arm_summaries),
        "n_tasks_planned": len(verified.basin_ids) * len(seeds) * len(verified.arms),
        "registered_hashes": verified.registered_hashes,
        "arms": arm_summaries,
        "failure": failure,
    }
    _write_root_summary(output, root_summary)
    return root_summary


def _parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True)
    parser.add_argument("--config-sha256", required=True)
    parser.add_argument("--workers", type=int, default=4)
    return parser.parse_args(argv)


def main(argv=None) -> int:
    arguments = _parse_args(argv)
    try:
        summary = run_registered_parameter_design(
            arguments.config,
            arguments.config_sha256,
            arguments.workers,
        )
    except Exception as error:  # noqa: BLE001 - command must stop and report
        print(f"STOP: {type(error).__name__}: {error}", file=sys.stderr)
        return 1
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0 if summary["execution_status"] == "complete" else 1


if __name__ == "__main__":
    raise SystemExit(main())
