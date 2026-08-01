"""Calibrated single-store linear-reservoir reference method."""

from __future__ import annotations


CATEGORY = "conceptual_rainfall_runoff"
CANDIDATE_ID = "reference-conceptual-rainfall-runoff-v1"
METHOD_FAMILY = "linear_reservoir"


def _fit_line(states: list[float], observed: list[float]) -> tuple[float, float, float]:
    mean_state = sum(states) / len(states)
    mean_observed = sum(observed) / len(observed)
    variance = sum((value - mean_state) ** 2 for value in states)
    scale = 0.0 if variance == 0.0 else sum(
        (state - mean_state) * (target - mean_observed) for state, target in zip(states, observed)
    ) / variance
    offset = mean_observed - scale * mean_state
    error = sum((offset + scale * state - target) ** 2 for state, target in zip(states, observed))
    return float(scale), float(offset), float(error)


def _states(rows: list[dict], decay: float) -> list[float]:
    state = 0.0
    values = []
    for row in rows:
        state = decay * state + row["prcp"]
        values.append(float(state))
    return values


def train_model(features: list[dict], targets: dict[tuple[str, str], float], statics: dict, seed: int) -> dict:
    del statics, seed
    grouped: dict[str, list[dict]] = {}
    for row in features:
        grouped.setdefault(row["basin"], []).append(row)
    parameters = {}
    all_observed = list(targets.values())
    for basin, rows in sorted(grouped.items()):
        ordered = sorted(rows, key=lambda item: item["date_key"])
        observed = [targets[(row["basin"], row["date_key"])] for row in ordered]
        best = None
        for decay in (0.0, 0.5, 0.8, 0.95):
            scale, offset, error = _fit_line(_states(ordered, decay), observed)
            candidate = (error, decay, scale, offset)
            if best is None or candidate < best:
                best = candidate
        _, decay, scale, offset = best
        parameters[basin] = {"decay": decay, "scale": scale, "offset": offset}
    return {"parameters": parameters, "global_mean": sum(all_observed) / len(all_observed)}


def predict(features: list[dict], statics: dict, model: dict) -> list[float]:
    del statics
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
        states = _states(ordered, float(parameters["decay"]))
        for row, state in zip(ordered, states):
            by_key[(basin, row["date_key"])] = float(parameters["offset"] + parameters["scale"] * state)
    return [by_key[(row["basin"], row["date_key"])] for row in features]
