"""Independently verify the deterministic updated-state ranking audit."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import numpy as np


PROJECT_ROOT = Path(__file__).resolve().parents[3]
SRC_ROOT = PROJECT_ROOT / "src"
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from hbv_joint_uncertainty.hbv_adapter import PARAMETER_NAMES  # noqa: E402
from hbv_multilead_joint_uncertainty.synthetic_truth import (  # noqa: E402
    advance_reference_state,
    reference_routed_discharge,
)


DEFAULT_RESULT = (
    PROJECT_ROOT
    / "results/23_hbv_multilead_joint_uncertainty/"
    "g3_deterministic_updated_state_ranking_v01"
)
METHODS = (
    "open_loop",
    "fixed_filter",
    "parameter_only",
    "noise_only",
    "joint",
    "truth_state_oracle",
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _maximum_difference(left, right) -> float:
    left_values = np.asarray(left, dtype=np.float64)
    right_values = np.asarray(right, dtype=np.float64)
    if left_values.shape != right_values.shape:
        return float("inf")
    return float(np.max(np.abs(left_values - right_values), initial=0.0))


def _reference_forecast(state, parameter_vector, forcing):
    parameters = {
        name: float(value)
        for name, value in zip(PARAMETER_NAMES, parameter_vector)
    }
    current = np.asarray(state, dtype=np.float64).copy()
    result = np.empty(7, dtype=np.float64)
    for lead in range(1, 8):
        current = advance_reference_state(current, *forcing[lead - 1], parameters)
        result[lead - 1] = reference_routed_discharge(
            current, parameters["lag_time"]
        )
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--result-dir", type=Path, default=DEFAULT_RESULT)
    args = parser.parse_args()
    result_dir = args.result_dir.resolve()
    config = json.loads(
        (result_dir / "config_snapshot.json").read_text(encoding="utf-8")
    )
    source = PROJECT_ROOT / config["sealed_ideal_evidence"]["path"]
    if _sha256(source) != config["sealed_ideal_evidence"]["sha256"]:
        raise ValueError("sealed ideal evidence SHA-256 mismatch")
    with np.load(result_dir / "evidence.npz", allow_pickle=False) as archive:
        saved = {name: archive[name].copy() for name in archive.files}
    with np.load(source, allow_pickle=False) as evidence:
        methods = tuple(str(value) for value in evidence["method_names"])
        if methods != METHODS[:-1]:
            raise ValueError("sealed method order changed")
        assimilation_days = int(np.asarray(evidence["assimilation_days"]).item())
        schedule = np.asarray(evidence["truth_parameter_indices"], dtype=np.int64)
        parameters = np.asarray(evidence["parameter_vectors"], dtype=np.float64)
        origins = np.arange(assimilation_days, dtype=np.int64)
        leads = np.arange(1, 8, dtype=np.int64)
        targets = origins[:, None] + leads[None, :]
        same_stage = schedule[:, targets] == schedule[:, origins, None]
        warmup = int(np.asarray(evidence["warmup_days"]).item())
        forcing = np.asarray(evidence["forcing_blocks"], dtype=np.float64)[:, warmup:]
        method_states = np.asarray(
            evidence["method_assimilation_states"][:, :, :, :assimilation_days],
            dtype=np.float64,
        )
        truth_states = np.asarray(evidence["truth_states"], dtype=np.float64)[
            :, :, :assimilation_days
        ]
        states = {
            method: method_states[:, :, position]
            for position, method in enumerate(methods)
        }
        states["truth_state_oracle"] = truth_states
        truth_discharge = np.asarray(evidence["truth_discharge"], dtype=np.float64)
        truth_forecasts = np.empty((8, 3, 540, 7), dtype=np.float64)
        for block in range(8):
            for truth in range(3):
                truth_forecasts[block, truth] = truth_discharge[block, truth, targets]
        forecasts = {}
        for method_number, method in enumerate(METHODS, start=1):
            values = np.empty((8, 3, 540, 7), dtype=np.float64)
            for block in range(8):
                for truth in range(3):
                    for origin in range(540):
                        values[block, truth, origin] = _reference_forecast(
                            states[method][block, truth, origin],
                            parameters[schedule[truth, origin]],
                            forcing[block, origin + 1 : origin + 8],
                        )
            forecasts[method] = values
            print(f"independent state methods {method_number}/{len(METHODS)}", flush=True)

    bootstrap = saved["bootstrap_indices"]
    rmse = {}
    block_mse = {}
    for method in METHODS:
        squared = np.square(forecasts[method] - truth_forecasts)
        rmse[method] = np.empty(7)
        block_mse[method] = np.empty((8, 7))
        for lead in range(7):
            selected = squared[..., lead][:, same_stage[..., lead]]
            rmse[method][lead] = np.sqrt(np.mean(selected))
            block_mse[method][:, lead] = np.mean(selected, axis=1)
    ranking = np.asarray(
        [
            [method for method in sorted(METHODS, key=lambda name: rmse[name][lead])]
            for lead in range(7)
        ]
    )
    expected = {
        "lead_days": leads,
        "origin_indices": origins,
        "target_indices": targets,
        "same_stage_mask": same_stage,
        "truth_forecasts": truth_forecasts,
        "ranking": ranking,
    }
    for method in METHODS:
        expected[f"forecast__{method}"] = forecasts[method]
        expected[f"rmse__{method}"] = rmse[method]
        expected[f"block_mse__{method}"] = block_mse[method]
    for baseline in METHODS:
        if baseline == "parameter_only":
            continue
        difference = block_mse["parameter_only"] - block_mse[baseline]
        boot = np.mean(difference[bootstrap], axis=1)
        prefix = f"comparison__parameter_only__minus__{baseline}"
        expected[f"{prefix}__mean_mse_difference"] = np.mean(difference, axis=0)
        expected[f"{prefix}__ci_low"] = np.quantile(boot, 0.025, axis=0)
        expected[f"{prefix}__ci_high"] = np.quantile(boot, 0.975, axis=0)
        relative = np.full(7, np.nan, dtype=np.float64)
        stable = rmse[baseline] > 1e-12
        relative[stable] = (
            rmse["parameter_only"][stable] / rmse[baseline][stable] - 1.0
        )
        expected[f"{prefix}__relative_rmse_fraction"] = relative
        expected[f"{prefix}__block_mse_difference"] = difference

    differences = {}
    for name, value in expected.items():
        if name == "ranking":
            continue
        if name.endswith("__relative_rmse_fraction"):
            saved_values = np.asarray(saved[name], dtype=np.float64)
            expected_values = np.asarray(value, dtype=np.float64)
            if not np.array_equal(np.isnan(saved_values), np.isnan(expected_values)):
                differences[name] = float("inf")
            else:
                finite = np.isfinite(expected_values)
                differences[name] = _maximum_difference(
                    saved_values[finite], expected_values[finite]
                )
        else:
            differences[name] = _maximum_difference(saved[name], value)
    label_checks = {
        "method_names": tuple(saved["method_names"].astype(str)) == METHODS,
        "ranking": np.array_equal(saved["ranking"].astype(str), ranking),
    }
    tolerance = float(config["numerical_tolerance"])
    passed = all(value <= tolerance for value in differences.values()) and all(
        label_checks.values()
    )
    report = {
        "status": "passed" if passed else "failed",
        "independent_reference_model": True,
        "production_forecast_module_imported": False,
        "tolerance": tolerance,
        "maximum_absolute_differences": differences,
        "maximum_absolute_difference_overall": max(differences.values()),
        "label_checks": label_checks,
        "evidence_sha256": _sha256(result_dir / "evidence.npz"),
        "sealed_ideal_evidence_sha256": _sha256(source),
    }
    (result_dir / "independent_verification.json").write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(report, indent=2))
    if not passed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
