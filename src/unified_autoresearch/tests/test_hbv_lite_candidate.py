"""The first real candidate: a calibrated HBV-lite bucket model.

Real means the method is a hydrological model with mass balance and a snow store, not a
placeholder curve fit. These tests pin the physics that make it a model rather than a
regression, and the reproducibility the pipeline depends on.
"""

import json
import math

import pytest

from unified_autoresearch.candidates.implementations import hbv_lite


PARAMETER_NAMES = ("tt", "cfmax", "fc", "beta", "lp", "perc", "k_fast", "k_slow")


def _statics(basins, *, pet_mean: float = 2.0) -> dict:
    from unified_autoresearch.selection.basins import APPROVED_STATIC_ATTRIBUTES

    return {
        "schema_version": "development_static_attributes_v1",
        "basins": {
            basin: {name: (pet_mean if name == "pet_mean" else 1.0) for name in APPROVED_STATIC_ATTRIBUTES}
            for basin in basins
        },
    }


def _rows(basin: str, days: int, *, prcp=None, tmean: float = 10.0, start: int = 0) -> list[dict]:
    rows = []
    for index in range(days):
        day = start + index
        rows.append(
            {
                "basin": basin,
                "date": f"2000-01-{day + 1:02d}",
                "date_key": f"day-{day:05d}",
                "prcp": float(prcp(day) if callable(prcp) else (2.0 if prcp is None else prcp)),
                "tmin": float(tmean - 3.0),
                "tmax": float(tmean + 3.0),
                "srad": 150.0,
                "vp": 1000.0,
            }
        )
    return rows


def _targets(rows: list[dict], value: float = 1.0) -> dict:
    return {(row["basin"], row["date_key"]): value for row in rows}


def test_identity_declares_a_conceptual_rainfall_runoff_method():
    assert hbv_lite.CATEGORY == "conceptual_rainfall_runoff"
    assert hbv_lite.CANDIDATE_ID == "hbv-lite-calibrated-v1"
    assert hbv_lite.METHOD_FAMILY == "hbv_lite_bucket"


def test_simulation_conserves_mass_within_the_stores():
    parameters = dict(zip(PARAMETER_NAMES, (0.0, 3.0, 200.0, 2.0, 0.6, 1.5, 0.15, 0.02)))
    rows = _rows("01000001", 200, prcp=lambda day: 5.0 if day % 3 == 0 else 0.0)

    result = hbv_lite.simulate(rows, parameters, pet_scale=0.3, report_balance=True)

    total_in = sum(row["prcp"] for row in rows)
    total_out = sum(result["discharge"]) + result["evaporation"] + result["storage_change"]
    assert total_out == pytest.approx(total_in, rel=1e-9, abs=1e-9)


def test_discharge_is_never_negative_and_always_finite():
    parameters = dict(zip(PARAMETER_NAMES, (1.0, 2.0, 120.0, 1.4, 0.5, 2.0, 0.3, 0.05)))
    rows = _rows("01000001", 300, prcp=lambda day: (day % 7) * 4.0, tmean=5.0)

    discharge = hbv_lite.simulate(rows, parameters, pet_scale=0.5)["discharge"]

    assert len(discharge) == len(rows)
    assert all(value >= 0.0 and math.isfinite(value) for value in discharge)


def test_precipitation_below_the_threshold_is_held_as_snow_and_released_when_it_warms():
    parameters = dict(zip(PARAMETER_NAMES, (0.0, 5.0, 150.0, 1.0, 0.6, 1.0, 0.2, 0.01)))
    frozen = _rows("01000001", 30, prcp=4.0, tmean=-10.0)
    thaw = _rows("01000001", 30, prcp=0.0, tmean=10.0, start=30)

    dry = _rows("01000001", 30, prcp=0.0, tmean=-10.0)
    frozen_only = hbv_lite.simulate(frozen, parameters, pet_scale=0.0, report_balance=True)
    dry_only = hbv_lite.simulate(dry, parameters, pet_scale=0.0, report_balance=True)
    with_thaw = hbv_lite.simulate(frozen + thaw, parameters, pet_scale=0.0, report_balance=True)

    assert frozen_only["snowpack"] == pytest.approx(120.0)
    # Below the threshold every millimetre is held back: the hydrograph is the same as if it
    # had never rained, and what does leave is the initial lower-zone store draining.
    assert frozen_only["discharge"] == dry_only["discharge"]
    assert with_thaw["snowpack"] == pytest.approx(0.0, abs=1e-9)
    assert sum(with_thaw["discharge"]) > sum(frozen_only["discharge"])


def test_potential_evaporation_is_scaled_to_the_frozen_static_attribute():
    rows = _rows("01000001", 400, tmean=12.0)

    scale = hbv_lite.potential_evaporation_scale(rows, pet_mean=2.5)
    shape = hbv_lite.temperature_shape(rows)

    assert sum(value * scale for value in shape) / len(rows) == pytest.approx(2.5)


def test_potential_evaporation_never_uses_shortwave_radiation():
    """Hargreaves with SRAD instead of extraterrestrial radiation is a known trap here."""
    warm = _rows("01000001", 50, tmean=12.0)
    bright = [dict(row, srad=900.0) for row in warm]

    assert hbv_lite.temperature_shape(warm) == hbv_lite.temperature_shape(bright)


def test_training_produces_a_json_serialisable_model_with_one_parameter_set_per_basin():
    basins = ["01000001", "01000002"]
    rows = [row for basin in basins for row in _rows(basin, 120, prcp=lambda day: (day % 5) * 3.0)]

    payload = hbv_lite.train_model(rows, _targets(rows, 1.2), _statics(basins), seed=11)

    assert set(payload["basins"]) == set(basins)
    for entry in payload["basins"].values():
        assert set(entry["parameters"]) == set(PARAMETER_NAMES)
        assert all(math.isfinite(value) for value in entry["parameters"].values())
        assert math.isfinite(entry["pet_scale"])
    assert json.loads(json.dumps(payload)) == payload


def test_training_is_reproducible_for_a_given_seed_and_responds_to_a_different_one():
    basins = ["01000001"]
    rows = _rows("01000001", 150, prcp=lambda day: (day % 4) * 4.0)
    targets = _targets(rows, 1.5)

    first = hbv_lite.train_model(rows, targets, _statics(basins), seed=7)
    again = hbv_lite.train_model(rows, targets, _statics(basins), seed=7)
    other = hbv_lite.train_model(rows, targets, _statics(basins), seed=8)

    assert first == again
    assert other != first


def test_calibration_improves_on_the_untuned_starting_point():
    basins = ["01000001"]
    rows = _rows("01000001", 200, prcp=lambda day: 8.0 if day % 6 == 0 else 0.5)
    truth = {
        key: 0.5 + 0.4 * ((index % 6) == 1)
        for index, key in enumerate(_targets(rows).keys())
    }

    payload = hbv_lite.train_model(rows, truth, _statics(basins), seed=3)
    entry = payload["basins"]["01000001"]

    assert entry["training_objective"] >= entry["initial_objective"]


def test_prediction_returns_one_value_per_input_row_in_the_given_order():
    basins = ["01000001", "01000002"]
    train_rows = [row for basin in basins for row in _rows(basin, 100, prcp=2.0)]
    payload = hbv_lite.train_model(train_rows, _targets(train_rows), _statics(basins), seed=5)
    predict_rows = [row for basin in reversed(basins) for row in _rows(basin, 40, prcp=3.0)]

    values = hbv_lite.predict(predict_rows, _statics(basins), payload)

    assert len(values) == len(predict_rows)
    assert all(math.isfinite(value) and value >= 0.0 for value in values)


def test_prediction_falls_back_without_raising_for_a_basin_absent_from_training():
    basins = ["01000001"]
    train_rows = _rows("01000001", 80, prcp=2.0)
    payload = hbv_lite.train_model(train_rows, _targets(train_rows), _statics(basins), seed=5)
    unseen = _rows("09999999", 20, prcp=2.0)

    values = hbv_lite.predict(unseen, _statics(basins + ["09999999"]), payload)

    assert len(values) == len(unseen)
    assert all(math.isfinite(value) and value >= 0.0 for value in values)


def test_prediction_does_not_depend_on_states_left_over_from_training():
    basins = ["01000001"]
    train_rows = _rows("01000001", 120, prcp=6.0)
    payload = hbv_lite.train_model(train_rows, _targets(train_rows), _statics(basins), seed=5)
    predict_rows = _rows("01000001", 60, prcp=1.0)

    first = hbv_lite.predict(predict_rows, _statics(basins), payload)
    second = hbv_lite.predict(predict_rows, _statics(basins), payload)

    assert first == second
    assert first == hbv_lite.simulate(
        predict_rows,
        payload["basins"]["01000001"]["parameters"],
        pet_scale=payload["basins"]["01000001"]["pet_scale"],
    )["discharge"]


def test_materialising_the_real_candidate_declares_its_own_identity_and_resources(tmp_path):
    from unified_autoresearch.candidates.catalog import materialize_hbv_lite_candidate

    materialized = materialize_hbv_lite_candidate(output_root=tmp_path / "candidate")

    descriptor = json.loads(materialized.descriptor_path.read_text(encoding="utf-8"))
    assert descriptor["candidate_id"] == "hbv-lite-calibrated-v1"
    assert descriptor["category"] == "conceptual_rainfall_runoff"
    assert descriptor["resources"]["independent_monitor_enabled"] is True
    assert descriptor["resources"]["cpu_cores"] == 1
    assert descriptor["resources"]["gpu_count"] == 0
    assert (materialized.source_root / "method.py").read_text(encoding="utf-8").startswith('"""HBV-lite')


def test_materialising_the_real_candidate_leaves_the_reference_candidates_unchanged(tmp_path):
    from unified_autoresearch.candidates.catalog import (
        materialize_hbv_lite_candidate,
        materialize_reference_candidate,
    )

    materialize_hbv_lite_candidate(output_root=tmp_path / "real")
    reference = materialize_reference_candidate(
        category="conceptual_rainfall_runoff", output_root=tmp_path / "reference"
    )

    descriptor = json.loads(reference.descriptor_path.read_text(encoding="utf-8"))
    assert descriptor["candidate_id"] == "reference-conceptual-rainfall-runoff-v1"
    assert descriptor["resources"]["independent_monitor_enabled"] is False
