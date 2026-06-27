"""Tests for the authoritative NSE and per-basin scoring."""
import numpy as np
import pandas as pd

from fair_benchmark.metrics import nse, per_basin_nse


def test_perfect_simulation_gives_nse_one():
    idx = pd.date_range("1990-01-01", periods=10, freq="D")
    obs = pd.Series(np.arange(10, dtype=float), index=idx)
    sim = obs.copy()
    assert nse(obs, sim) == 1.0


def test_mean_predictor_gives_nse_zero():
    idx = pd.date_range("1990-01-01", periods=11, freq="D")
    obs = pd.Series(np.arange(11, dtype=float), index=idx)
    sim = pd.Series(np.full(11, obs.mean()), index=idx)
    assert abs(nse(obs, sim)) < 1e-12


def test_nan_pairs_are_dropped_on_both_sides():
    idx = pd.date_range("1990-01-01", periods=5, freq="D")
    obs = pd.Series([1.0, 2.0, np.nan, 4.0, 5.0], index=idx)
    sim = pd.Series([1.0, 2.0, 99.0, np.nan, 5.0], index=idx)
    # only indices 0,1,4 are valid on both sides; sim==obs there -> NSE 1.0
    assert nse(obs, sim) == 1.0


def test_series_aligned_by_index_not_position():
    obs = pd.Series([1.0, 2.0, 3.0], index=pd.to_datetime(["1990-01-01", "1990-01-02", "1990-01-03"]))
    sim = pd.Series([3.0, 2.0, 1.0], index=pd.to_datetime(["1990-01-03", "1990-01-02", "1990-01-01"]))
    # after alignment sim == obs -> NSE 1.0 (would be wrong if compared by position)
    assert nse(obs, sim) == 1.0


def test_too_few_valid_points_returns_nan():
    idx = pd.date_range("1990-01-01", periods=3, freq="D")
    obs = pd.Series([1.0, np.nan, np.nan], index=idx)
    sim = pd.Series([1.0, 2.0, 3.0], index=idx)
    assert np.isnan(nse(obs, sim))


def test_zero_variance_obs_returns_nan():
    idx = pd.date_range("1990-01-01", periods=5, freq="D")
    obs = pd.Series(np.full(5, 7.0), index=idx)
    sim = pd.Series(np.arange(5, dtype=float), index=idx)
    assert np.isnan(nse(obs, sim))


def test_per_basin_nse_maps_each_basin():
    idx = pd.date_range("1990-01-01", periods=10, freq="D")
    obs = {
        "01022500": pd.Series(np.arange(10, dtype=float), index=idx),
        "01031500": pd.Series(np.arange(10, dtype=float) * 2, index=idx),
    }
    sim = {
        "01022500": obs["01022500"].copy(),                       # perfect -> 1.0
        "01031500": pd.Series(np.full(10, obs["01031500"].mean()), index=idx),  # mean -> 0.0
    }
    result = per_basin_nse(obs, sim)
    assert set(result) == {"01022500", "01031500"}
    assert result["01022500"] == 1.0
    assert abs(result["01031500"]) < 1e-12


def test_per_basin_nse_missing_basin_in_sim_is_nan():
    idx = pd.date_range("1990-01-01", periods=10, freq="D")
    obs = {"01022500": pd.Series(np.arange(10, dtype=float), index=idx)}
    sim = {}  # challenger failed to predict this basin
    result = per_basin_nse(obs, sim)
    assert np.isnan(result["01022500"])


def test_per_basin_score_uses_given_metric():
    from fair_benchmark.metrics import per_basin_score
    idx = pd.date_range("1990-01-01", periods=5, freq="D")
    obs = {"a": pd.Series([1.0, 2.0, 3.0, 4.0, 5.0], index=idx)}
    sim = {"a": pd.Series([1.0, 2.0, 3.0, 4.0, 5.0], index=idx)}

    def neg_mae(o, s):
        o, s = o.align(s, join="inner")
        m = o.notna() & s.notna()
        return -float((o[m] - s[m]).abs().mean())

    assert per_basin_score(obs, sim, neg_mae)["a"] == 0.0  # perfect -> -0


def test_matches_neuralhydrology_authoritative_nse():
    """Our NSE must be numerically identical to the one authoritative impl."""
    import pytest
    try:
        import xarray as xr
        from neuralhydrology.evaluation.metrics import nse as nh_nse
    except Exception:  # pragma: no cover - env without nh/xarray
        pytest.skip("neuralhydrology/xarray not importable")
    rng = np.random.default_rng(0)
    o = rng.normal(5.0, 2.0, 300)
    s = o + rng.normal(0.0, 1.0, 300)
    o[::13] = np.nan
    s[::17] = np.nan
    idx = pd.date_range("1990-01-01", periods=300, freq="D")
    ours = nse(pd.Series(o, index=idx), pd.Series(s, index=idx))
    theirs = nh_nse(xr.DataArray(o, dims="date"), xr.DataArray(s, dims="date"))
    assert abs(ours - theirs) < 1e-10
