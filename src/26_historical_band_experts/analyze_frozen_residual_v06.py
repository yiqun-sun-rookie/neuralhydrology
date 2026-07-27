"""Analyze the frozen-recent residual candidate on the internal validation period."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Mapping

import numpy as np
import pandas as pd

from metrics import per_basin_nse
from train_equal_experts_v06 import _atomic_frame, _atomic_text
from train_frozen_residual_v06 import validate_frozen_residual_config_v06
from train_v05 import validate_frozen_file_hash


_REPO = Path(__file__).resolve().parents[2]


def evaluate_stage1_frozen_residual_v06(
    paired: pd.DataFrame,
    gates: Mapping,
) -> dict:
    delta_classic = paired["nse_candidate"] - paired["nse_classic"]
    delta_capacity = paired["nse_candidate"] - paired["nse_capacity"]
    delta_late = paired["nse_candidate"] - paired["nse_late_concat"]
    values = {
        "n_basins": int(len(paired)),
        "median_delta_classic": float(np.nanmedian(delta_classic)),
        "median_delta_capacity": float(np.nanmedian(delta_capacity)),
        "median_delta_late_concat": float(np.nanmedian(delta_late)),
        "win_fraction_classic": float(np.mean(delta_classic > 0)),
    }
    criteria = {
        "median_delta_classic_at_least": (
            values["median_delta_classic"] >= float(gates["median_delta_classic_at_least"])
        ),
        "median_delta_capacity_above": (
            values["median_delta_capacity"] > float(gates["median_delta_capacity_above"])
        ),
        "median_delta_late_concat_above": (
            values["median_delta_late_concat"] > float(gates["median_delta_late_concat_above"])
        ),
        "win_fraction_classic_at_least": (
            values["win_fraction_classic"] >= float(gates["win_fraction_classic_at_least"])
        ),
    }
    return {**values, "criteria": criteria, "passed": bool(all(criteria.values()))}


def _load_predictions(path: Path) -> pd.DataFrame:
    frame = pd.read_csv(path, dtype={"basin": str})
    expected_columns = ["basin", "date", "qobs", "qsim"]
    if list(frame.columns) != expected_columns:
        raise ValueError(f"prediction columns are invalid in {path}")
    if len(frame) != 43_860:
        raise ValueError(f"prediction row count must be 43860 in {path}")
    return frame.sort_values(["basin", "date"]).reset_index(drop=True)


def _assert_same_targets(reference: pd.DataFrame, candidate: pd.DataFrame, label: str) -> None:
    if not candidate[["basin", "date"]].equals(reference[["basin", "date"]]):
        raise ValueError(f"{label} prediction keys differ")
    if not np.array_equal(candidate["qobs"].to_numpy(), reference["qobs"].to_numpy()):
        raise ValueError(f"{label} observations differ")


def _named_nse_v06(predictions: pd.DataFrame, name: str) -> pd.DataFrame:
    return per_basin_nse(predictions)[["basin", "nse"]].rename(
        columns={"nse": f"nse_{name}"}
    )


def analyze_frozen_residual_v06(config: Mapping) -> dict:
    validate_frozen_residual_config_v06(config)
    if config["mode"] != "pilot":
        raise ValueError("formal stage-one analysis requires pilot mode")
    for path_key, hash_key, label in (
        ("classic_predictions", "classic_predictions_sha256", "classic predictions"),
        ("capacity_predictions", "capacity_predictions_sha256", "capacity predictions"),
        ("late_concat_predictions", "late_concat_predictions_sha256", "late-concat predictions"),
    ):
        validate_frozen_file_hash(_REPO / config[path_key], config[hash_key], label)
    candidate_path = (
        _REPO
        / config["results_root"]
        / f"frozen_recent_equal_experts_s{config['stage1_seed']}"
        / "predictions.csv"
    )
    if not candidate_path.exists():
        result = {
            "status": "incomplete",
            "missing_runs": [str(candidate_path.relative_to(_REPO))],
            "required_conditional_seeds": [],
        }
        root = _REPO / config["results_root"]
        root.mkdir(parents=True, exist_ok=True)
        _atomic_text(root / "summary.json", json.dumps(result, indent=2, sort_keys=True))
        return result

    paths = {
        "classic": _REPO / config["classic_predictions"],
        "capacity": _REPO / config["capacity_predictions"],
        "late_concat": _REPO / config["late_concat_predictions"],
        "candidate": candidate_path,
    }
    predictions = {name: _load_predictions(path) for name, path in paths.items()}
    reference = predictions["classic"]
    for name, frame in predictions.items():
        _assert_same_targets(reference, frame, name)
    metrics = {}
    for name, frame in predictions.items():
        metrics[name] = _named_nse_v06(frame, name)
    paired = metrics["classic"]
    for name in ("capacity", "late_concat", "candidate"):
        paired = paired.merge(metrics[name], on="basin", how="inner", validate="one_to_one")
    if len(paired) != 60:
        raise ValueError(f"paired basin count must be 60, got {len(paired)}")
    paired = paired.sort_values("basin").reset_index(drop=True)
    stage1 = evaluate_stage1_frozen_residual_v06(paired, config["stage1_gates"])
    passed = bool(stage1["passed"])
    summary = {
        "status": "complete_stage1_pass" if passed else "complete_stage1_no_go",
        "missing_runs": [],
        "required_conditional_seeds": list(config["conditional_seeds"]) if passed else [],
        "stage1": stage1,
    }
    root = _REPO / config["results_root"]
    _atomic_frame(root / "paired_per_basin.csv", paired)
    _atomic_text(root / "summary.json", json.dumps(summary, indent=2, sort_keys=True))
    return summary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    args = parser.parse_args()
    config = json.loads(args.config.read_text(encoding="utf-8"))
    summary = analyze_frozen_residual_v06(config)
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
