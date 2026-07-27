"""Staged paired analysis for equal historical experts iteration 1."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path

import numpy as np
import pandas as pd

from metrics import per_basin_nse


_REPO = Path(__file__).resolve().parents[2]
_VARIANTS = (
    "classic_lstm_256_keyed",
    "classic_lstm_455_keyed",
    "late_concat_keyed",
    "equal_experts",
)


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _atomic_text(path: Path, content: str) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(content, encoding="utf-8")
    os.replace(temporary, path)


def evaluate_stage1_equal_v06(paired: pd.DataFrame, gates: dict) -> dict:
    """Apply the frozen seed-100 paired gates."""
    required = {
        "nse_classic",
        "nse_capacity",
        "nse_late_concat",
        "nse_candidate",
    }
    missing = required - set(paired.columns)
    if missing:
        raise ValueError(f"paired metrics are missing columns: {sorted(missing)}")
    delta_classic = (paired["nse_candidate"] - paired["nse_classic"]).to_numpy(float)
    delta_capacity = (paired["nse_candidate"] - paired["nse_capacity"]).to_numpy(float)
    delta_late = (paired["nse_candidate"] - paired["nse_late_concat"]).to_numpy(float)
    median_classic = float(np.nanmedian(delta_classic))
    median_capacity = float(np.nanmedian(delta_capacity))
    median_late = float(np.nanmedian(delta_late))
    win_fraction = float(np.nanmean(delta_classic > 0))
    criteria = {
        "median_delta_classic_at_least": (
            median_classic >= float(gates["median_delta_classic_at_least"])
        ),
        "median_delta_capacity_above": (
            median_capacity > float(gates["median_delta_capacity_above"])
        ),
        "median_delta_late_concat_above": (
            median_late > float(gates["median_delta_late_concat_above"])
        ),
        "win_fraction_classic_at_least": (
            win_fraction >= float(gates["win_fraction_classic_at_least"])
        ),
    }
    return {
        "passed": bool(all(criteria.values())),
        "criteria": {key: bool(value) for key, value in criteria.items()},
        "median_delta_classic": median_classic,
        "median_delta_capacity": median_capacity,
        "median_delta_late_concat": median_late,
        "win_fraction_classic": win_fraction,
        "n_basins": int(np.isfinite(delta_classic).sum()),
    }


def _validated_metrics(run_dir: Path, variant: str, seed: int) -> pd.DataFrame:
    manifest_path = run_dir / "manifest.json"
    predictions_path = run_dir / "predictions.csv"
    if not manifest_path.exists() or not predictions_path.exists():
        raise FileNotFoundError(f"missing completed run: {run_dir}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("status") != "complete":
        raise ValueError(f"run is not complete: {run_dir}")
    if manifest.get("variant") != variant or int(manifest.get("seed", -1)) != seed:
        raise ValueError(f"run identity mismatch: {run_dir}")
    for name, expected in manifest.get("artifacts", {}).items():
        if _sha256(run_dir / name) != expected:
            raise ValueError(f"artifact hash mismatch for {run_dir / name}")
    predictions = pd.read_csv(predictions_path, dtype={"basin": str})
    saved = pd.read_csv(run_dir / "per_basin_metrics.csv", dtype={"basin": str})
    recomputed = per_basin_nse(predictions)
    pd.testing.assert_frame_equal(saved, recomputed, check_exact=True)
    return recomputed


def analyze_equal_results_v06(config: dict) -> dict:
    """Analyze the four seed-100 runs against the frozen legacy late-concat result."""
    results_root = _REPO / config["results_root"]
    locations = {
        variant: results_root / f"{variant}_s{int(config['stage1_seed'])}"
        for variant in _VARIANTS
    }
    missing = [
        variant for variant, path in locations.items()
        if not (path / "manifest.json").exists()
    ]
    if missing:
        return {"status": "incomplete_stage1", "missing_runs": missing}
    metrics = {
        variant: _validated_metrics(path, variant, int(config["stage1_seed"]))
        for variant, path in locations.items()
    }
    paired = metrics["classic_lstm_256_keyed"][["basin", "nse"]].rename(
        columns={"nse": "nse_classic"}
    )
    paired = paired.merge(
        metrics["classic_lstm_455_keyed"][["basin", "nse"]].rename(
            columns={"nse": "nse_capacity"}
        ),
        on="basin",
    )
    paired = paired.merge(
        metrics["late_concat_keyed"][["basin", "nse"]].rename(
            columns={"nse": "nse_late_concat_keyed"}
        ),
        on="basin",
    )
    paired = paired.merge(
        metrics["equal_experts"][["basin", "nse"]].rename(
            columns={"nse": "nse_candidate"}
        ),
        on="basin",
    )

    legacy_run = _REPO / config["legacy_late_concat_run_dir"]
    legacy_predictions = legacy_run / "predictions.csv"
    if _sha256(legacy_predictions) != config["legacy_late_concat_predictions_sha256"]:
        raise ValueError("legacy late-concat predictions SHA-256 mismatch")
    legacy_metrics = per_basin_nse(pd.read_csv(legacy_predictions, dtype={"basin": str}))
    paired = paired.merge(
        legacy_metrics[["basin", "nse"]].rename(columns={"nse": "nse_late_concat"}),
        on="basin",
    )
    stage1 = evaluate_stage1_equal_v06(paired, config["stage1_gates"])
    stage1["median_delta_late_concat_keyed"] = float(np.nanmedian(
        paired["nse_candidate"] - paired["nse_late_concat_keyed"]
    ))
    summary = {
        "status": "complete_stage1_go" if stage1["passed"] else "complete_stage1_no_go",
        "missing_runs": [],
        "stage1": stage1,
        "required_conditional_seeds": [200, 300] if stage1["passed"] else [],
    }
    results_root.mkdir(parents=True, exist_ok=True)
    paired.to_csv(results_root / "paired_per_basin.csv", index=False)
    _atomic_text(results_root / "summary.json", json.dumps(summary, indent=2, sort_keys=True))
    return summary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    args = parser.parse_args()
    config = json.loads(args.config.read_text(encoding="utf-8"))
    print(json.dumps(analyze_equal_results_v06(config), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
