from src.xaj_global_pilot.classification import classify_regime, qc_record


def test_classify_regime_uses_snow_first():
    record = {
        "snow_fraction": 0.30,
        "temp_coldest_quarter": -3.0,
        "cold_season_precip_fraction": 0.35,
        "aridity_index": 2.2,
    }
    assert classify_regime(record) == "snow-dominated"


def test_classify_regime_uses_aridity_for_non_snow():
    record = {
        "snow_fraction": 0.05,
        "temp_coldest_quarter": 4.0,
        "cold_season_precip_fraction": 0.10,
        "aridity_index": 1.2,
    }
    assert classify_regime(record) == "semi-humid"


def test_qc_record_rejects_high_missing_rate():
    record = {"missing_rate": 0.08, "human_impact_flag": False, "split_coverage_ok": True}
    assert qc_record(record) is False
