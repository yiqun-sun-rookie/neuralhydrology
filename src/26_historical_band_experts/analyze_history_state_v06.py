"""Analyze the frozen-recent history-state candidate."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Mapping

import pandas as pd

from analyze_frozen_residual_v06 import (
    _assert_same_targets,
    _load_predictions,
    _named_nse_v06,
    evaluate_stage1_frozen_residual_v06,
)
from train_equal_experts_v06 import _atomic_frame, _atomic_text
from train_history_state_v06 import validate_history_state_config_v06
from train_v05 import validate_frozen_file_hash


_REPO = Path(__file__).resolve().parents[2]


def analyze_history_state_v06(config: Mapping) -> dict:
    validate_history_state_config_v06(config)
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
        / f"frozen_recent_history_state_s{config['stage1_seed']}"
        / "predictions.csv"
    )
    root = _REPO / config["results_root"]
    if not candidate_path.exists():
        result = {
            "status": "incomplete",
            "missing_runs": [str(candidate_path.relative_to(_REPO))],
            "required_conditional_seeds": [],
        }
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
    metrics = {
        name: _named_nse_v06(frame, name)
        for name, frame in predictions.items()
    }
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
    _atomic_frame(root / "paired_per_basin.csv", paired)
    _atomic_text(root / "summary.json", json.dumps(summary, indent=2, sort_keys=True))
    return summary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    args = parser.parse_args()
    config = json.loads(args.config.read_text(encoding="utf-8"))
    print(json.dumps(analyze_history_state_v06(config), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
