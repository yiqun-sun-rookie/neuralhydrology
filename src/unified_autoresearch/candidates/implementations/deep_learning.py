"""Deterministic two-hidden-layer multilayer perceptron implemented with NumPy."""

from __future__ import annotations

import numpy as np


CATEGORY = "deep_learning"
CANDIDATE_ID = "reference-deep-learning-v1"
METHOD_FAMILY = "multilayer_perceptron"


def _schema(features: list[dict], statics: dict) -> tuple[list[str], list[str]]:
    basins = sorted({row["basin"] for row in features})
    attribute_names = sorted(next(iter(statics["basins"].values())))
    return basins, attribute_names


def _vector(row: dict, statics: dict, basins: list[str], attribute_names: list[str]) -> list[float]:
    attributes = statics["basins"][row["basin"]]
    return [
        row["prcp"],
        row["tmin"],
        row["tmax"],
        row["srad"],
        row["vp"],
        *[float(attributes[name]) for name in attribute_names],
        *[1.0 if row["basin"] == basin else 0.0 for basin in basins],
    ]


def train_model(features: list[dict], targets: dict[tuple[str, str], float], statics: dict, seed: int) -> dict:
    basins, attribute_names = _schema(features, statics)
    x = np.asarray([_vector(row, statics, basins, attribute_names) for row in features], dtype=np.float64)
    y = np.asarray([targets[(row["basin"], row["date_key"])] for row in features], dtype=np.float64)[:, None]
    x_mean = x.mean(axis=0)
    x_scale = x.std(axis=0)
    x_scale[x_scale == 0.0] = 1.0
    y_mean = float(y.mean())
    y_scale = float(y.std()) or 1.0
    x = (x - x_mean) / x_scale
    y = (y - y_mean) / y_scale

    generator = np.random.default_rng(seed)
    w1 = generator.normal(0.0, 0.12, size=(x.shape[1], 8))
    b1 = np.zeros((1, 8), dtype=np.float64)
    w2 = generator.normal(0.0, 0.12, size=(8, 4))
    b2 = np.zeros((1, 4), dtype=np.float64)
    w3 = generator.normal(0.0, 0.12, size=(4, 1))
    b3 = np.zeros((1, 1), dtype=np.float64)
    learning_rate = 0.02
    for _ in range(200):
        h1 = np.tanh(x @ w1 + b1)
        h2 = np.tanh(h1 @ w2 + b2)
        prediction = h2 @ w3 + b3
        output_gradient = 2.0 * (prediction - y) / len(y)
        w3_gradient = h2.T @ output_gradient
        b3_gradient = output_gradient.sum(axis=0, keepdims=True)
        h2_gradient = (output_gradient @ w3.T) * (1.0 - h2 * h2)
        w2_gradient = h1.T @ h2_gradient
        b2_gradient = h2_gradient.sum(axis=0, keepdims=True)
        h1_gradient = (h2_gradient @ w2.T) * (1.0 - h1 * h1)
        w1_gradient = x.T @ h1_gradient
        b1_gradient = h1_gradient.sum(axis=0, keepdims=True)
        w3 -= learning_rate * w3_gradient
        b3 -= learning_rate * b3_gradient
        w2 -= learning_rate * w2_gradient
        b2 -= learning_rate * b2_gradient
        w1 -= learning_rate * w1_gradient
        b1 -= learning_rate * b1_gradient
    return {
        "basins": basins,
        "attribute_names": attribute_names,
        "x_mean": x_mean.tolist(),
        "x_scale": x_scale.tolist(),
        "y_mean": y_mean,
        "y_scale": y_scale,
        "weights": {
            "w1": w1.tolist(),
            "b1": b1.tolist(),
            "w2": w2.tolist(),
            "b2": b2.tolist(),
            "w3": w3.tolist(),
            "b3": b3.tolist(),
        },
    }


def predict(features: list[dict], statics: dict, model: dict) -> list[float]:
    x = np.asarray(
        [_vector(row, statics, model["basins"], model["attribute_names"]) for row in features],
        dtype=np.float64,
    )
    x = (x - np.asarray(model["x_mean"])) / np.asarray(model["x_scale"])
    weights = model["weights"]
    h1 = np.tanh(x @ np.asarray(weights["w1"]) + np.asarray(weights["b1"]))
    h2 = np.tanh(h1 @ np.asarray(weights["w2"]) + np.asarray(weights["b2"]))
    normalized = h2 @ np.asarray(weights["w3"]) + np.asarray(weights["b3"])
    values = normalized[:, 0] * float(model["y_scale"]) + float(model["y_mean"])
    return [float(value) for value in values]
