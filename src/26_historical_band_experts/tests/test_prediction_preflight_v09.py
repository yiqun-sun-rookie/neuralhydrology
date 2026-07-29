from pathlib import Path
import sys

import numpy as np
import pandas as pd
import pytest


IDEA_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IDEA_ROOT))


def _frame() -> pd.DataFrame:
    return pd.DataFrame({
        "basin": ["00000001"] * 3 + ["00000002"] * 3,
        "date": list(pd.date_range("2000-01-01", periods=3).strftime("%Y-%m-%d")) * 2,
        "qsim": np.arange(6, dtype=np.float64),
    })


def test_v09_prediction_preflight_requires_exact_unique_finite_coverage(tmp_path):
    from prediction_preflight_v09 import validate_exact_prediction_coverage_v09

    path = tmp_path / "predictions.csv"
    _frame().to_csv(path, index=False)

    report = validate_exact_prediction_coverage_v09(
        path,
        basin_ids=("00000001", "00000002"),
        start_date="2000-01-01",
        end_date="2000-01-03",
        chunk_rows=2,
    )

    assert report == {
        "status": "exact_coverage",
        "basin_count": 2,
        "dates_per_basin": 3,
        "row_count": 6,
        "duplicate_count": 0,
        "missing_count": 0,
        "nonfinite_count": 0,
    }


@pytest.mark.parametrize("failure", ("duplicate", "missing", "nonfinite", "extra_column", "unknown_basin"))
def test_v09_prediction_preflight_rejects_malformed_submission(tmp_path, failure):
    from prediction_preflight_v09 import PredictionPreflightError, validate_exact_prediction_coverage_v09

    frame = _frame()
    if failure == "duplicate":
        frame = pd.concat((frame, frame.iloc[[0]]), ignore_index=True)
    elif failure == "missing":
        frame = frame.iloc[:-1].copy()
    elif failure == "nonfinite":
        frame.loc[0, "qsim"] = np.nan
    elif failure == "extra_column":
        frame["qobs"] = 1.0
    else:
        frame.loc[0, "basin"] = "99999999"
    path = tmp_path / f"{failure}.csv"
    frame.to_csv(path, index=False)

    with pytest.raises(PredictionPreflightError, match=failure.replace("_", " ")):
        validate_exact_prediction_coverage_v09(
            path,
            basin_ids=("00000001", "00000002"),
            start_date="2000-01-01",
            end_date="2000-01-03",
            chunk_rows=2,
        )


def test_v09_eight_seed_mean_uses_fixed_order_and_float64(tmp_path):
    from prediction_preflight_v09 import compose_seed_mean_v09, validate_exact_prediction_coverage_v09

    paths = []
    base = _frame()
    for index, seed in enumerate(range(100, 801, 100)):
        frame = base.copy()
        frame["qsim"] = frame["qsim"].astype(np.float32) + np.float32(index)
        path = tmp_path / f"seed_{seed}.csv"
        frame.to_csv(path, index=False)
        paths.append(path)

    output = tmp_path / "ensemble.csv"
    report = compose_seed_mean_v09(paths, output, chunk_rows=2)
    ensemble = pd.read_csv(output, dtype={"basin": str})

    assert report["seed_count"] == 8
    assert report["row_count"] == 6
    assert report["accumulator_dtype"] == "float64"
    np.testing.assert_allclose(ensemble["qsim"], base["qsim"] + 3.5, rtol=0, atol=0)
    assert validate_exact_prediction_coverage_v09(
        output,
        basin_ids=("00000001", "00000002"),
        start_date="2000-01-01",
        end_date="2000-01-03",
        chunk_rows=2,
    )["status"] == "exact_coverage"


def test_v09_seed_mean_rejects_key_order_mismatch_without_output(tmp_path):
    from prediction_preflight_v09 import PredictionPreflightError, compose_seed_mean_v09

    paths = []
    for index, seed in enumerate(range(100, 801, 100)):
        frame = _frame()
        if index == 4:
            frame = frame.iloc[::-1].reset_index(drop=True)
        path = tmp_path / f"seed_{seed}.csv"
        frame.to_csv(path, index=False)
        paths.append(path)
    output = tmp_path / "ensemble.csv"

    with pytest.raises(PredictionPreflightError, match="key order"):
        compose_seed_mean_v09(paths, output, chunk_rows=2)
    assert not output.exists()


def test_v09_seed_mean_rejects_nonpositive_chunk_size(tmp_path):
    from prediction_preflight_v09 import compose_seed_mean_v09

    with pytest.raises(ValueError, match="chunk_rows"):
        compose_seed_mean_v09([], tmp_path / "ensemble.csv", chunk_rows=0)
