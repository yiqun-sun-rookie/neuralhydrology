"""Equal fusion of a reservoir response and static-aware forcing regression."""

from __future__ import annotations

import numpy as np


CATEGORY = "fusion"
CANDIDATE_ID = "reference-fusion-v1"
METHOD_FAMILY = "reservoir_regression_fusion"


def _static_mean(statics: dict, basin: str) -> float:
    values = statics["basins"][basin].values()
    return float(sum(values) / len(statics["basins"][basin]))


def _design(row: dict, statics: dict) -> list[float]:
    return [
        1.0,
        row["prcp"],
        (row["tmin"] + row["tmax"]) / 2.0,
        row["srad"] / 100.0,
        row["vp"] / 1000.0,
        _static_mean(statics, row["basin"]),
    ]


def _reservoir_states(rows: list[dict]) -> list[float]:
    state = 0.0
    result = []
    for row in rows:
        state = 0.8 * state + row["prcp"]
        result.append(float(state))
    return result


def train_model(features: list[dict], targets: dict[tuple[str, str], float], statics: dict, seed: int) -> dict:
    del seed
    grouped: dict[str, list[dict]] = {}
    for row in features:
        grouped.setdefault(row["basin"], []).append(row)
    result = {}
    for basin, rows in sorted(grouped.items()):
        ordered = sorted(rows, key=lambda item: item["date_key"])
        observed = np.asarray(
            [targets[(row["basin"], row["date_key"])] for row in ordered], dtype=np.float64
        )
        design = np.asarray([_design(row, statics) for row in ordered], dtype=np.float64)
        beta = np.linalg.lstsq(design, observed, rcond=None)[0]
        states = np.asarray(_reservoir_states(ordered), dtype=np.float64)
        reservoir_design = np.column_stack([np.ones(len(states)), states])
        reservoir_beta = np.linalg.lstsq(reservoir_design, observed, rcond=None)[0]
        result[basin] = {
            "regression_beta": beta.tolist(),
            "reservoir_beta": reservoir_beta.tolist(),
        }
    return {"parameters": result, "global_mean": float(sum(targets.values()) / len(targets))}


def predict(features: list[dict], statics: dict, model: dict) -> list[float]:
    grouped: dict[str, list[dict]] = {}
    for row in features:
        grouped.setdefault(row["basin"], []).append(row)
    by_key = {}
    for basin, rows in grouped.items():
        ordered = sorted(rows, key=lambda item: item["date_key"])
        parameters = model["parameters"].get(basin)
        if parameters is None:
            for row in ordered:
                by_key[(basin, row["date_key"])] = float(model["global_mean"])
            continue
        regression_beta = np.asarray(parameters["regression_beta"], dtype=np.float64)
        reservoir_beta = np.asarray(parameters["reservoir_beta"], dtype=np.float64)
        states = _reservoir_states(ordered)
        for row, state in zip(ordered, states):
            regression = float(np.asarray(_design(row, statics)) @ regression_beta)
            reservoir = float(reservoir_beta[0] + reservoir_beta[1] * state)
            by_key[(basin, row["date_key"])] = regression / 2.0 + reservoir / 2.0
    return [by_key[(row["basin"], row["date_key"])] for row in features]
