import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

import pytest
import numpy as np
import pandas as pd
import torch
from scl_hydro.dataset import SCLDataset


@pytest.fixture
def synthetic_data():
    """Create synthetic basin data for testing."""
    n_days = 400
    dates = pd.date_range("2000-01-01", periods=n_days, freq="D")
    df = pd.DataFrame({
        "prcp": np.random.rand(n_days),
        "tmax": np.random.rand(n_days) * 30,
        "QObs": np.abs(np.random.randn(n_days)) + 0.1,
    }, index=dates)
    return {"basin_01": df}


def test_scl_dataset_getitem_keys(synthetic_data):
    """__getitem__ should return all required keys."""
    ds = SCLDataset(
        data=synthetic_data,
        seg_length=30,
        context_length=10,
        overlap_length=10,
        main_features=["prcp", "tmax"],
        enc_features=["prcp", "tmax", "QObs"],
        target="QObs",
    )
    assert len(ds) > 0
    sample = ds[0]
    required_keys = {"context_k", "predict_k", "context_k1", "predict_k1",
                     "y_k", "y_k1"}
    assert required_keys.issubset(sample.keys())


def test_scl_dataset_shapes(synthetic_data):
    """All tensors should have correct shapes."""
    seg_len = 30
    ctx_len = 10
    overlap = 10
    n_main = 2
    n_enc = 3
    ds = SCLDataset(
        data=synthetic_data,
        seg_length=seg_len,
        context_length=ctx_len,
        overlap_length=overlap,
        main_features=["prcp", "tmax"],
        enc_features=["prcp", "tmax", "QObs"],
        target="QObs",
    )
    sample = ds[0]
    assert sample["context_k"].shape == (ctx_len, n_enc)
    assert sample["predict_k"].shape == (seg_len, n_main)
    assert sample["context_k1"].shape == (ctx_len, n_enc)
    assert sample["predict_k1"].shape == (seg_len, n_main)
    assert sample["y_k"].shape == (seg_len, 1)
    assert sample["y_k1"].shape == (seg_len, 1)


def test_scl_dataset_temporal_overlap(synthetic_data):
    """The overlap region of seg_k and seg_k+1 should cover the same dates."""
    seg_len = 30
    overlap = 10
    ds = SCLDataset(
        data=synthetic_data,
        seg_length=seg_len,
        context_length=10,
        overlap_length=overlap,
        main_features=["prcp", "tmax"],
        enc_features=["prcp", "tmax", "QObs"],
        target="QObs",
    )
    sample = ds[0]
    # Last overlap_length of y_k should equal first overlap_length of y_k1
    y_k_overlap = sample["y_k"][-overlap:]
    y_k1_overlap = sample["y_k1"][:overlap]
    torch.testing.assert_close(y_k_overlap, y_k1_overlap)
