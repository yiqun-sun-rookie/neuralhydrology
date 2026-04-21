from src.xaj_global_pilot.config import (
    COLD_QUARTER_TEMP_THRESHOLD_C,
    COLD_SEASON_PRECIP_FRACTION_THRESHOLD,
    HUMID_MAX_ARIDITY,
    MISSING_RATE_THRESHOLD,
    SEMI_HUMID_MAX_ARIDITY,
    SNOW_FRACTION_THRESHOLD,
)


def classify_regime(record: dict) -> str:
    snow_fraction = _as_float(record.get("snow_fraction"), default=0.0)
    temp_coldest_quarter = _as_float(record.get("temp_coldest_quarter"), default=99.0)
    cold_season_precip_fraction = _as_float(record.get("cold_season_precip_fraction"), default=0.0)
    aridity_index = _as_float(record.get("aridity_index"), default=0.0)

    snow_dominated = snow_fraction >= SNOW_FRACTION_THRESHOLD or (
        temp_coldest_quarter < COLD_QUARTER_TEMP_THRESHOLD_C
        and cold_season_precip_fraction >= COLD_SEASON_PRECIP_FRACTION_THRESHOLD
    )
    if snow_dominated:
        return "snow-dominated"
    if aridity_index < HUMID_MAX_ARIDITY:
        return "humid"
    if aridity_index < SEMI_HUMID_MAX_ARIDITY:
        return "semi-humid"
    return "semi-arid/arid"


def qc_record(record: dict) -> bool:
    split_coverage_ok = bool(record.get("split_coverage_ok", True))
    missing_rate = _as_float(record.get("missing_rate"), default=1.0)
    human_impact_flag = bool(record.get("human_impact_flag", False))
    if not split_coverage_ok:
        return False
    if missing_rate > MISSING_RATE_THRESHOLD:
        return False
    if human_impact_flag:
        return False
    return True


def _as_float(value, default: float) -> float:
    if value is None:
        return default
    return float(value)
