from pathlib import Path
from collections import OrderedDict


BENCHMARK_NAME = "global_conceptual_model_benchmark"
SCREENING_VERSION = "screening_v02"
FULL_VERSION = "camels_us_531_v02"
REPRO_VERSION = "camels_us_531_repro_v01"
DEFAULT_CALIBRATION_TRIALS = 5000
DEFAULT_RESTARTS = 3
WARMUP_DAYS = 365

PILOT_NAME = "xaj_global_pilot"
PILOT_VERSION = "pilot_v01"
SUMMARY_DIRNAME = "summary"

REGIME_SAMPLE_SIZE = 15
REGIME_NAMES = (
    "snow-dominated",
    "humid",
    "semi-humid",
    "semi-arid/arid",
)

SNOW_FRACTION_THRESHOLD = 0.20
COLD_QUARTER_TEMP_THRESHOLD_C = 0.0
COLD_SEASON_PRECIP_FRACTION_THRESHOLD = 0.20
MISSING_RATE_THRESHOLD = 0.05
MAX_BASINS_PER_REGION = 5

HUMID_MAX_ARIDITY = 1.0
SEMI_HUMID_MAX_ARIDITY = 1.5

MINIMUM_REGISTRY_COLUMNS = (
    "basin_id",
    "region",
    "aridity_index",
    "snow_fraction",
    "missing_rate",
    "regime",
    "selected_for_pilot",
)

TRAIN_START_DATE = "1990-10-01"
TRAIN_END_DATE = "1995-09-30"
VALIDATION_START_DATE = "1995-10-01"
VALIDATION_END_DATE = "2000-09-30"
TEST_START_DATE = "2000-10-01"
TEST_END_DATE = "2005-09-30"

# ---------------------------------------------------------------------------
# repro_v01 protocol (benchmark-aligned track).
#
# Calibration / evaluation periods and forcing match the published CAMELS
# benchmark used by the SAC-SMA / VIC / FUSE / HBV / mHM ensemble on
# CUAHSI HydroShare (resource 474ecc37e7db45baa425cdb4fc1b61e1) and adopted
# verbatim by Kratzert et al. 2019 (HESS 23, 5089-5110). Verified against
# kratzert/ealstm_regional_modeling main.py GLOBAL_SETTINGS and
# papercode/utils.py::load_forcing.
#
# Calibration: 1 Oct 1999 -> 30 Sep 2008  (9 water years)
# Evaluation:  1 Oct 1989 -> 30 Sep 1999  (10 water years)
# Forcing:     maurer (NOT daymet; see note below on maurer vs maurer_extended)
#
# These are LOCKED per the alignment plan; do not change without re-anchoring
# the comparison ladder in docs/technical/camels_us_531_published_target.md.
#
# Note on forcing choice. The published Kratzert 2019 ealstm repo reads from
# `basin_mean_forcing/maurer_extended`, but `maurer_extended` is just the
# Maurer et al. 2002 dataset extended in time to 2014; in the 1980-2008
# overlap window (which fully covers BOTH our calibration and evaluation
# segments) the data is byte-equivalent to `maurer`. We point at `maurer`
# because it is what the project's local + HPC data tree actually has.
# Override via the runner's `--forcing maurer_extended` if a future
# environment ships only the extended subdir.
# ---------------------------------------------------------------------------
REPRO_CALIBRATION_START_DATE = "1999-10-01"
REPRO_CALIBRATION_END_DATE = "2008-09-30"
REPRO_EVALUATION_START_DATE = "1989-10-01"
REPRO_EVALUATION_END_DATE = "1999-09-30"
REPRO_FORCING = "maurer"

# v02 forcing label (daymet) — keeps protocol-dispatch consistent and
# documents that the exploratory baseline used a different forcing dataset.
V02_FORCING = "daymet"


def benchmark_results_dir(version: str = SCREENING_VERSION) -> Path:
    return Path("results") / "10_global_conceptual_model_benchmark" / version


def benchmark_logs_dir(version: str = SCREENING_VERSION) -> Path:
    return Path("logs") / "10_global_conceptual_model_benchmark" / version


def benchmark_summary_dir(version: str = SCREENING_VERSION) -> Path:
    return benchmark_results_dir(version) / SUMMARY_DIRNAME


def benchmark_configs_dir() -> Path:
    return Path("src") / "xaj_global_pilot" / "configs"


def pilot_results_dir() -> Path:
    return Path("results") / PILOT_NAME / PILOT_VERSION


def pilot_logs_dir() -> Path:
    return Path("logs") / PILOT_NAME / PILOT_VERSION


def pilot_summary_dir() -> Path:
    return pilot_results_dir() / SUMMARY_DIRNAME


def split_periods() -> OrderedDict[str, tuple[str, str]]:
    return OrderedDict(
        [
            ("train", (TRAIN_START_DATE, TRAIN_END_DATE)),
            ("validation", (VALIDATION_START_DATE, VALIDATION_END_DATE)),
            ("test", (TEST_START_DATE, TEST_END_DATE)),
        ]
    )


def repro_split_periods() -> OrderedDict[str, tuple[str, str]]:
    """Benchmark-aligned two-segment split used by repro_v01 protocol."""
    return OrderedDict(
        [
            ("calibration", (REPRO_CALIBRATION_START_DATE, REPRO_CALIBRATION_END_DATE)),
            ("evaluation", (REPRO_EVALUATION_START_DATE, REPRO_EVALUATION_END_DATE)),
        ]
    )
