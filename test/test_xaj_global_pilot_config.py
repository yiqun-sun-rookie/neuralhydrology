from src.xaj_global_pilot.config import (
    BENCHMARK_NAME,
    DEFAULT_CALIBRATION_TRIALS,
    DEFAULT_RESTARTS,
    FULL_VERSION,
    REGIME_NAMES,
    REGIME_SAMPLE_SIZE,
    SCREENING_VERSION,
    SUMMARY_DIRNAME,
    TEST_END_DATE,
    TEST_START_DATE,
    TRAIN_END_DATE,
    TRAIN_START_DATE,
    WARMUP_DAYS,
)


def test_benchmark_constants_are_stable():
    assert BENCHMARK_NAME == "global_conceptual_model_benchmark"
    assert SCREENING_VERSION == "screening_v02"
    assert FULL_VERSION == "camels_us_531_v02"
    assert DEFAULT_CALIBRATION_TRIALS == 5000
    assert DEFAULT_RESTARTS == 3
    assert WARMUP_DAYS == 365
    assert REGIME_SAMPLE_SIZE == 15
    assert REGIME_NAMES == (
        "snow-dominated",
        "humid",
        "semi-humid",
        "semi-arid/arid",
    )
    assert SUMMARY_DIRNAME == "summary"
    assert TRAIN_START_DATE == "1990-10-01"
    assert TRAIN_END_DATE == "1995-09-30"
    assert TEST_START_DATE == "2000-10-01"
    assert TEST_END_DATE == "2005-09-30"
