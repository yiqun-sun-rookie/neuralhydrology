"""Tests for knowledge separation result summarizer."""
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from pretrained_lstm_knowledge_separation.scripts.summarize_results import (
    aggregate_metrics,
    compute_gain_loss,
    build_summary_table,
)


@pytest.fixture
def fake_results() -> pd.DataFrame:
    """Simulated per-basin results for 8 adaptation runs.

    4 groups × 2 shifts, 5 basins each.
    Source baseline NSE per basin: 0.5 for all.
    """
    rows = []
    rng = np.random.RandomState(0)
    for shift in ["low_shift", "high_shift"]:
        for group in ["head", "embedding", "lstm", "full"]:
            for i in range(5):
                basin = f"{shift}_{i:04d}"
                # head does well on low_shift, poorly on high_shift
                if group == "head":
                    nse = 0.7 + rng.normal(0, 0.02) if shift == "low_shift" else 0.4 + rng.normal(0, 0.02)
                elif group == "full":
                    nse = 0.75 + rng.normal(0, 0.02)
                else:
                    nse = 0.6 + rng.normal(0, 0.05)
                rows.append({
                    "basin": basin,
                    "split_label": shift,
                    "adaptation_group": group,
                    "NSE": nse,
                    "source_NSE": 0.5,
                })
    return pd.DataFrame(rows)


def test_aggregate_metrics_returns_mean_per_group(fake_results):
    agg = aggregate_metrics(fake_results, metric="NSE")
    assert set(agg.columns) == {"low_shift", "high_shift"}
    assert set(agg.index) == {"head", "embedding", "lstm", "full"}
    assert all(agg.dtypes == np.float64)


def test_compute_gain_loss_counts(fake_results):
    gl = compute_gain_loss(fake_results, metric="NSE", baseline_col="source_NSE")
    assert "gain_count" in gl.columns
    assert "loss_count" in gl.columns
    assert "gain_frac" in gl.columns
    total = gl["gain_count"] + gl["loss_count"]
    assert (total == 5).all()  # 5 basins per cell


def test_build_summary_table_has_all_cells(fake_results):
    table = build_summary_table(fake_results, metric="NSE", baseline_col="source_NSE")
    assert table.shape[0] == 4  # 4 adaptation groups
    assert "low_shift_mean_NSE" in table.columns
    assert "high_shift_mean_NSE" in table.columns
    assert "low_shift_gain_frac" in table.columns
    assert "high_shift_gain_frac" in table.columns


def test_head_best_on_low_shift(fake_results):
    """Hypothesis 1: head-only should be competitive under low shift."""
    agg = aggregate_metrics(fake_results, metric="NSE")
    assert agg.loc["head", "low_shift"] > 0.6
