"""Tests for attribute-based shift split builder."""
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from pretrained_lstm_knowledge_separation.scripts.build_shift_splits import (
    compute_shift_distances,
    select_shift_groups,
)

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

DESCRIPTOR_COLS = ["aridity", "frac_snow", "elev_mean", "soil_depth_pelletier"]


@pytest.fixture
def fake_attributes() -> pd.DataFrame:
    """20 basins with known attribute structure.

    Basins 00-09 cluster near (0, 0, 0, 0).
    Basins 10-19 cluster near (5, 5, 5, 5) — far from center.
    """
    rng = np.random.RandomState(42)
    n = 20
    ids = [f"{i:08d}" for i in range(n)]
    data = {}
    for col in DESCRIPTOR_COLS:
        near = rng.normal(0, 0.3, size=10)
        far = rng.normal(5, 0.3, size=10)
        data[col] = np.concatenate([near, far])
    df = pd.DataFrame(data, index=ids)
    df.index.name = "gauge_id"
    return df


@pytest.fixture
def source_basins() -> list:
    """First 10 basins are 'source'."""
    return [f"{i:08d}" for i in range(10)]


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


def test_compute_shift_distances_returns_series(fake_attributes, source_basins):
    distances = compute_shift_distances(
        attributes=fake_attributes,
        source_basins=source_basins,
        descriptor_cols=DESCRIPTOR_COLS,
    )
    assert isinstance(distances, pd.Series)
    assert len(distances) == len(fake_attributes)
    assert distances.dtype == np.float64


def test_low_shift_closer_than_high_shift(fake_attributes, source_basins):
    distances = compute_shift_distances(
        attributes=fake_attributes,
        source_basins=source_basins,
        descriptor_cols=DESCRIPTOR_COLS,
    )
    low, high = select_shift_groups(
        distances=distances,
        source_basins=source_basins,
        n_per_group=5,
    )
    mean_low = distances.loc[low].mean()
    mean_high = distances.loc[high].mean()
    assert mean_low < mean_high


def test_group_sizes_match_request(fake_attributes, source_basins):
    distances = compute_shift_distances(
        attributes=fake_attributes,
        source_basins=source_basins,
        descriptor_cols=DESCRIPTOR_COLS,
    )
    low, high = select_shift_groups(
        distances=distances,
        source_basins=source_basins,
        n_per_group=5,
    )
    assert len(low) == 5
    assert len(high) == 5


def test_groups_are_disjoint(fake_attributes, source_basins):
    distances = compute_shift_distances(
        attributes=fake_attributes,
        source_basins=source_basins,
        descriptor_cols=DESCRIPTOR_COLS,
    )
    low, high = select_shift_groups(
        distances=distances,
        source_basins=source_basins,
        n_per_group=5,
    )
    assert set(low).isdisjoint(set(high))


def test_groups_exclude_source_basins(fake_attributes, source_basins):
    distances = compute_shift_distances(
        attributes=fake_attributes,
        source_basins=source_basins,
        descriptor_cols=DESCRIPTOR_COLS,
    )
    low, high = select_shift_groups(
        distances=distances,
        source_basins=source_basins,
        n_per_group=5,
    )
    assert set(low).isdisjoint(set(source_basins))
    assert set(high).isdisjoint(set(source_basins))


def test_reproducibility(fake_attributes, source_basins):
    distances1 = compute_shift_distances(
        attributes=fake_attributes,
        source_basins=source_basins,
        descriptor_cols=DESCRIPTOR_COLS,
    )
    distances2 = compute_shift_distances(
        attributes=fake_attributes,
        source_basins=source_basins,
        descriptor_cols=DESCRIPTOR_COLS,
    )
    pd.testing.assert_series_equal(distances1, distances2)

    low1, high1 = select_shift_groups(distances1, source_basins, n_per_group=5)
    low2, high2 = select_shift_groups(distances2, source_basins, n_per_group=5)
    assert low1 == low2
    assert high1 == high2
