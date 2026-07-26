from pathlib import Path
import copy
import hashlib
import json
import sys

import numpy as np
import pandas as pd
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from analyze import (
    analyze_results,
    evaluate_continuation,
    paired_bootstrap_interval,
)


def _passing_inputs():
    per_seed = pd.DataFrame(
        {
            "seed": [100, 200, 300],
            "median_delta_expert_fusion": [0.03, 0.02, 0.025],
            "win_fraction_expert_fusion": [0.70, 0.60, 0.65],
        }
    )
    paired = pd.DataFrame(
        {
            "basin": [f"{index:08d}" for index in range(20)],
            "delta_expert_fusion_mean": np.linspace(0.015, 0.04, 20),
            "delta_expert_mainstream_mean": np.linspace(0.001, 0.02, 20),
        }
    )
    weights = {"recent": 0.4, "medium": 0.35, "old": 0.25}
    return per_seed, paired, weights


def test_frozen_continuation_gate_passes_only_when_all_criteria_pass():
    per_seed, paired, weights = _passing_inputs()

    summary = evaluate_continuation(per_seed, paired, weights)

    assert summary["verdict"] == "GO"
    assert all(summary["criteria"].values())


@pytest.mark.parametrize(
    "criterion",
    [
        "median_effect",
        "basin_win_fraction",
        "two_seed_joint_consistency",
        "bootstrap_lower_above_zero",
        "not_worse_than_mainstream",
        "no_weight_collapse",
    ],
)
def test_each_failed_frozen_criterion_forces_no_go(criterion):
    per_seed, paired, weights = _passing_inputs()
    per_seed = per_seed.copy()
    paired = paired.copy()
    weights = copy.deepcopy(weights)
    if criterion == "median_effect":
        per_seed["median_delta_expert_fusion"] = [0.0, 0.0, 0.02]
    elif criterion == "basin_win_fraction":
        per_seed["win_fraction_expert_fusion"] = [0.2, 0.2, 0.8]
    elif criterion == "two_seed_joint_consistency":
        per_seed["median_delta_expert_fusion"] = [0.02, 0.0, 0.0]
        per_seed["win_fraction_expert_fusion"] = [0.8, 0.8, 0.2]
    elif criterion == "bootstrap_lower_above_zero":
        paired["delta_expert_fusion_mean"] = np.linspace(-0.05, 0.05, len(paired))
    elif criterion == "not_worse_than_mainstream":
        paired["delta_expert_mainstream_mean"] = -0.01
    elif criterion == "no_weight_collapse":
        weights = {"recent": 0.96, "medium": 0.02, "old": 0.02}

    summary = evaluate_continuation(per_seed, paired, weights)

    assert summary["verdict"] == "NO_GO"
    assert summary["criteria"][criterion] is False


def test_paired_bootstrap_is_deterministic():
    values = np.linspace(-0.01, 0.04, 30)

    first = paired_bootstrap_interval(values)
    second = paired_bootstrap_interval(values)

    assert first == second
    assert first[0] < first[1]


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _write_run(root: Path, variant: str, seed: int, qsim_offset: float):
    run_dir = root / f"{variant}_s{seed}"
    run_dir.mkdir(parents=True)
    rows = []
    for basin_index in range(3):
        basin = f"{basin_index + 1:08d}"
        for day, observed in enumerate([0.0, 1.0, 2.0, 3.0]):
            row = {
                "basin": basin,
                "date": f"2007-01-{day + 1:02d}",
                "qobs": observed,
                "qsim": observed + qsim_offset,
            }
            if variant == "historical_band_experts":
                row.update(
                    weight_recent=0.4,
                    weight_medium=0.35,
                    weight_old=0.25,
                )
            rows.append(row)
    predictions_path = run_dir / "predictions.csv"
    pd.DataFrame(rows).to_csv(predictions_path, index=False)
    manifest = {
        "status": "complete",
        "variant": variant,
        "seed": seed,
        "artifacts": {"predictions.csv": _sha256(predictions_path)},
    }
    (run_dir / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")


def test_end_to_end_analysis_recomputes_predictions_and_writes_go(tmp_path):
    for seed in (100, 200, 300):
        _write_run(tmp_path, "mainstream_lstm", seed, qsim_offset=0.6)
        _write_run(tmp_path, "multiscale_fusion", seed, qsim_offset=0.8)
        _write_run(tmp_path, "historical_band_experts", seed, qsim_offset=0.2)

    summary = analyze_results(tmp_path)

    assert summary["verdict"] == "GO"
    assert (tmp_path / "summary.json").exists()
    assert (tmp_path / "per_seed.csv").exists()
    assert (tmp_path / "paired_per_basin.csv").exists()


def test_missing_run_is_incomplete_not_go(tmp_path):
    _write_run(tmp_path, "mainstream_lstm", 100, qsim_offset=0.6)

    summary = analyze_results(tmp_path)

    assert summary["verdict"] == "INCOMPLETE"
    assert summary["missing_runs"]
