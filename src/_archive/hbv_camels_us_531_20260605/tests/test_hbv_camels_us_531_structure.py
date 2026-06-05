from src.hbv_camels_us_531.config import (
    TEST_END_DATE,
    TEST_START_DATE,
    TRAIN_END_DATE,
    TRAIN_START_DATE,
    VALIDATION_END_DATE,
    VALIDATION_START_DATE,
)
from src.hbv_camels_us_531.structure import build_fixed_hbv_structure


def test_dates_match_531_benchmark():
    assert TRAIN_START_DATE == "1990-10-01"
    assert TRAIN_END_DATE == "1995-09-30"
    assert VALIDATION_START_DATE == "1995-10-01"
    assert VALIDATION_END_DATE == "2000-09-30"
    assert TEST_START_DATE == "2000-10-01"
    assert TEST_END_DATE == "2005-09-30"


def test_fixed_structure_has_expected_components():
    structure = build_fixed_hbv_structure()

    assert structure["model_name"] == "hbv_camels_us_531_fixed_v1"
    assert [layer["type"] for layer in structure["layers"]] == [
        "SnowReservoir",
        "UnsaturatedReservoir",
        "PowerReservoir",
        "LinearReservoir",
    ]
    assert structure["lags"] == [{"type": "HalfTriangularLag", "target": "fast", "lag_steps": 2.0}]


def test_fixed_structure_exposes_environment_compatible_lag_functions():
    structure = build_fixed_hbv_structure()

    assert structure["lag_functions"] == structure["lags"]
