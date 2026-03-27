"""Tests for representation drift analysis helpers."""
import sys
from pathlib import Path

import numpy as np
import pytest
import torch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from pretrained_lstm_knowledge_separation.scripts.analyze_representations import (
    cosine_distance,
    euclidean_distance,
    linear_cka,
    aggregate_drift_by_module,
)


@pytest.fixture
def identical_tensors():
    rng = np.random.RandomState(42)
    t = torch.tensor(rng.randn(50, 128), dtype=torch.float32)
    return t, t.clone()


@pytest.fixture
def orthogonal_tensors():
    t1 = torch.eye(128, dtype=torch.float32)[:50]
    t2 = torch.zeros(50, 128, dtype=torch.float32)
    # shift columns to make them orthogonal
    t2[:, 64:] = t1[:, :64]
    return t1, t2


# ---------------------------------------------------------------------------
# cosine distance
# ---------------------------------------------------------------------------


def test_cosine_distance_identical_is_zero(identical_tensors):
    a, b = identical_tensors
    d = cosine_distance(a, b)
    assert d == pytest.approx(0.0, abs=1e-5)


def test_cosine_distance_orthogonal_is_one(orthogonal_tensors):
    a, b = orthogonal_tensors
    d = cosine_distance(a, b)
    assert d == pytest.approx(1.0, abs=0.05)


# ---------------------------------------------------------------------------
# euclidean distance
# ---------------------------------------------------------------------------


def test_euclidean_distance_identical_is_zero(identical_tensors):
    a, b = identical_tensors
    d = euclidean_distance(a, b)
    assert d == pytest.approx(0.0, abs=1e-5)


def test_euclidean_distance_positive():
    a = torch.zeros(10, 64)
    b = torch.ones(10, 64)
    d = euclidean_distance(a, b)
    assert d > 0


# ---------------------------------------------------------------------------
# linear CKA
# ---------------------------------------------------------------------------


def test_linear_cka_identical_is_one(identical_tensors):
    a, b = identical_tensors
    cka = linear_cka(a, b)
    assert cka == pytest.approx(1.0, abs=1e-4)


def test_linear_cka_in_range():
    rng = np.random.RandomState(0)
    a = torch.tensor(rng.randn(50, 128), dtype=torch.float32)
    b = torch.tensor(rng.randn(50, 128), dtype=torch.float32)
    cka = linear_cka(a, b)
    assert 0.0 <= cka <= 1.0


# ---------------------------------------------------------------------------
# aggregate drift
# ---------------------------------------------------------------------------


def test_aggregate_drift_by_module():
    rng = np.random.RandomState(0)
    source_acts = {
        "embedding": torch.tensor(rng.randn(20, 64), dtype=torch.float32),
        "lstm_output": torch.tensor(rng.randn(20, 128), dtype=torch.float32),
        "head_input": torch.tensor(rng.randn(20, 128), dtype=torch.float32),
    }
    adapted_acts = {
        "embedding": torch.tensor(rng.randn(20, 64), dtype=torch.float32),
        "lstm_output": torch.tensor(rng.randn(20, 128), dtype=torch.float32),
        "head_input": torch.tensor(rng.randn(20, 128), dtype=torch.float32),
    }
    drift = aggregate_drift_by_module(source_acts, adapted_acts)
    assert set(drift.keys()) == {"embedding", "lstm_output", "head_input"}
    for v in drift.values():
        assert "cosine_distance" in v
        assert "linear_cka" in v
        assert 0.0 <= v["linear_cka"] <= 1.0
