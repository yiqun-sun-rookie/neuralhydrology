"""Independently verify H06-H08 metrics from saved daily arrays."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

import numpy as np


METHODS = ("fixed", "learned_static", "history_conditioned")


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _oracle(
    modes: np.ndarray,
    switch_days: np.ndarray,
    minimum_duration: int,
    maximum_duration: int,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    block_count, days = modes.shape
    source = modes.copy()
    source[:, 1:] = modes[:, :-1]
    expected = np.zeros((block_count, days, 3), dtype=np.float64)
    hazard = np.zeros((block_count, days), dtype=np.float64)
    evaluation = np.zeros((block_count, days), dtype=bool)
    for block in range(block_count):
        first, second = (int(value) for value in switch_days[block])
        for start, stop in ((0, first), (first, second)):
            duration = stop - start
            if duration < minimum_duration or duration > maximum_duration:
                raise ValueError("saved switch schedule violates the duration contract")
            for day in range(start + 1, stop + 1):
                age = day - start
                day_hazard = (
                    0.0
                    if age < minimum_duration
                    else 1.0 / float(maximum_duration - age + 1)
                )
                expected[block, day] = day_hazard / 2.0
                expected[block, day, source[block, day]] = 1.0 - day_hazard
                hazard[block, day] = day_hazard
                evaluation[block, day] = True
    return source, expected, hazard, evaluation


def _method_metrics(
    *,
    arrays: Any,
    method: str,
    minimum_duration: int,
    maximum_duration: int,
) -> tuple[dict[str, float], bool]:
    modes = arrays["truth_parameter_indices"]
    truth_discharge = arrays["truth_discharge"]
    switch_days = arrays["switch_days"]
    leads = tuple(int(value) for value in arrays["forecast_leads"])
    flow_standard_deviation = float(arrays["flow_standard_deviation"])
    matrices = arrays[f"{method}_transition_matrices"]
    forecasts = arrays[f"{method}_forecast_discharge"]
    saved_valid = arrays[f"{method}_forecast_valid_mask"]
    block_count, days = modes.shape
    extended_modes = np.pad(
        modes,
        ((0, 0), (0, max(leads))),
        mode="edge",
    )

    errors = []
    valid_masks = []
    for lead_index, lead in enumerate(leads):
        target = truth_discharge[:, lead : lead + days]
        target_modes = extended_modes[:, lead : lead + days]
        valid = modes == target_modes
        errors.append(
            ((forecasts[:, :, lead_index] - target) / flow_standard_deviation) ** 2
        )
        valid_masks.append(valid)
    error_tensor = np.stack(errors, axis=-1)
    valid_mask = np.stack(valid_masks, axis=-1)
    valid_matches = bool(np.array_equal(saved_valid, valid_mask))
    forecast_loss = float(np.mean(error_tensor[valid_mask]))

    post_switch_origin = np.zeros((block_count, days), dtype=bool)
    for block in range(block_count):
        for switch in switch_days[block]:
            start = int(switch)
            post_switch_origin[block, start : min(start + 7, days)] = True
    post_switch_loss = float(
        np.mean(error_tensor[valid_mask & post_switch_origin[..., None]])
    )

    source, expected, oracle_hazard, evaluation = _oracle(
        modes,
        switch_days,
        minimum_duration,
        maximum_duration,
    )
    block_indices = np.arange(block_count)[:, None]
    day_indices = np.arange(days)[None, :]
    active_rows = matrices[block_indices, day_indices, source]
    predicted = active_rows[evaluation]
    oracle_rows = expected[evaluation]
    predicted_hazard = 1.0 - predicted[
        np.arange(predicted.shape[0]), source[evaluation]
    ]
    oracle_brier = float(
        np.mean(np.sum((predicted - oracle_rows) ** 2, axis=-1))
    )
    hazard_mae = float(
        np.mean(np.abs(predicted_hazard - oracle_hazard[evaluation]))
    )
    return (
        {
            "maximum_transition_row_sum_error": float(
                np.max(np.abs(matrices.sum(axis=-1) - 1.0))
            ),
            "minimum_transition_probability": float(np.min(matrices)),
            "forecast": forecast_loss,
            "post_switch_days_0_to_6_forecast_loss": post_switch_loss,
            "oracle_brier": oracle_brier,
            "switch_hazard_mean_absolute_error": hazard_mae,
        },
        valid_matches,
    )


def verify_result_directory(path: str | Path) -> dict[str, Any]:
    root = Path(path).resolve()
    config = json.loads((root / "config_snapshot.json").read_text(encoding="utf-8"))
    metrics = json.loads((root / "metrics.json").read_text(encoding="utf-8"))
    gradients = json.loads(
        (root / "gradient_audit.json").read_text(encoding="utf-8")
    )
    checksums = json.loads((root / "checksums.json").read_text(encoding="utf-8"))
    checksum_matches = {
        name: (root / name).is_file() and _sha256(root / name) == expected
        for name, expected in checksums.items()
    }
    arrays = np.load(root / "daily_arrays.npz", allow_pickle=False)
    data = config["data"]
    recomputed = {}
    valid_mask_matches = {}
    differences = []
    for method in METHODS:
        values, valid_matches = _method_metrics(
            arrays=arrays,
            method=method,
            minimum_duration=int(data["minimum_regime_duration_days"]),
            maximum_duration=int(data["maximum_regime_duration_days"]),
        )
        recomputed[method] = values
        valid_mask_matches[method] = valid_matches
        saved = metrics["methods"][method]
        pairs = (
            (values["maximum_transition_row_sum_error"], saved["maximum_transition_row_sum_error"]),
            (values["minimum_transition_probability"], saved["minimum_transition_probability"]),
            (values["forecast"], saved["losses"]["forecast"]),
            (
                values["post_switch_days_0_to_6_forecast_loss"],
                saved["post_switch_days_0_to_6_forecast_loss"],
            ),
            (values["oracle_brier"], saved["transition_recovery"]["oracle_brier"]),
            (
                values["switch_hazard_mean_absolute_error"],
                saved["transition_recovery"]["switch_hazard_mean_absolute_error"],
            ),
        )
        differences.extend(abs(float(left) - float(right)) for left, right in pairs)

    learned_static = recomputed["learned_static"]
    history = recomputed["history_conditioned"]
    comparisons = {
        "relative_oracle_brier_reduction": (
            learned_static["oracle_brier"] - history["oracle_brier"]
        )
        / learned_static["oracle_brier"],
        "relative_switch_hazard_mae_reduction": (
            learned_static["switch_hazard_mean_absolute_error"]
            - history["switch_hazard_mean_absolute_error"]
        )
        / learned_static["switch_hazard_mean_absolute_error"],
        "relative_post_switch_forecast_loss_reduction": (
            learned_static["post_switch_days_0_to_6_forecast_loss"]
            - history["post_switch_days_0_to_6_forecast_loss"]
        )
        / learned_static["post_switch_days_0_to_6_forecast_loss"],
        "relative_overall_forecast_loss_increase": (
            history["forecast"] - learned_static["forecast"]
        )
        / learned_static["forecast"],
    }
    for name, value in comparisons.items():
        differences.append(
            abs(float(value) - float(metrics["history_vs_learned_static"][name]))
        )

    maximum_difference = max(differences, default=0.0)
    all_verified = (
        all(checksum_matches.values())
        and all(valid_mask_matches.values())
        and maximum_difference <= 1e-12
        and float(
            gradients["maximum_absolute_total_objective_gradient_to_network"]
        )
        > 0.0
        and float(gradients["maximum_absolute_current_observation_gradient"])
        == 0.0
        and float(gradients["maximum_absolute_future_observation_gradient"])
        == 0.0
    )
    return {
        "experiment_id": config["experiment_id"],
        "all_checksums_match": all(checksum_matches.values()),
        "all_forecast_valid_masks_match": all(valid_mask_matches.values()),
        "maximum_saved_metric_absolute_difference": maximum_difference,
        "total_objective_gradient_to_network": gradients[
            "maximum_absolute_total_objective_gradient_to_network"
        ],
        "current_observation_gradient": gradients[
            "maximum_absolute_current_observation_gradient"
        ],
        "future_observation_gradient": gradients[
            "maximum_absolute_future_observation_gradient"
        ],
        "methods": recomputed,
        "history_vs_learned_static": comparisons,
        "all_verified": all_verified,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("result_directories", nargs="+")
    arguments = parser.parse_args()
    results = [
        verify_result_directory(path) for path in arguments.result_directories
    ]
    print(json.dumps(results, indent=2, sort_keys=True))
    if not all(result["all_verified"] for result in results):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
