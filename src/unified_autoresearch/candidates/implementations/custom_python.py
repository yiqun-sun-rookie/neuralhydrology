"""Per-basin training mean reference method."""

from __future__ import annotations


CATEGORY = "custom_python"
CANDIDATE_ID = "reference-custom-python-v1"
METHOD_FAMILY = "per_basin_mean"


def train_model(features: list[dict], targets: dict[tuple[str, str], float], statics: dict, seed: int) -> dict:
    del statics, seed
    grouped: dict[str, list[float]] = {}
    for row in features:
        grouped.setdefault(row["basin"], []).append(targets[(row["basin"], row["date_key"])])
    all_values = [value for values in grouped.values() for value in values]
    return {
        "basin_means": {basin: sum(values) / len(values) for basin, values in sorted(grouped.items())},
        "global_mean": sum(all_values) / len(all_values),
    }


def predict(features: list[dict], statics: dict, model: dict) -> list[float]:
    del statics
    return [float(model["basin_means"].get(row["basin"], model["global_mean"])) for row in features]
