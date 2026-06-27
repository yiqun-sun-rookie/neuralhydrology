"""Build the Track-0 ALLOWED-DATA BUNDLE (the Level-1 data tap).

Contains ONLY what a Track-0 challenger may use: the 5 Maurer forcing variables
+ the 27 CAMELS static attributes, over [warmup_start, eval_end]. Observed
discharge is NOT included anywhere — the challenger reads this bundle, never the
answer key. Doubles as the dataset the agent EDAs to understand the data.

Run from repo root:  python -m fair_benchmark.build_allowed_bundle
"""
from pathlib import Path

import pandas as pd

_REPO = Path(__file__).resolve().parents[2]
_DATA = _REPO / "data/camels_us"
_FROZEN = Path(__file__).resolve().parent / "frozen"
_BUNDLE = _FROZEN / "bundle"
_BASINS_SRC = _REPO / "src/xaj_global_pilot/configs/conceptual_benchmark_camels_us_531_repro.txt"

DYN = ["PRCP(mm/day)", "Tmin(C)", "Tmax(C)", "SRAD(W/m2)", "Vp(Pa)"]
STATIC_27 = [
    "p_mean", "pet_mean", "aridity", "p_seasonality", "frac_snow",
    "high_prec_freq", "high_prec_dur", "low_prec_freq", "low_prec_dur",
    "elev_mean", "slope_mean", "area_gages2", "frac_forest", "lai_max",
    "lai_diff", "gvf_max", "gvf_diff", "soil_depth_pelletier",
    "soil_depth_statsgo", "soil_porosity", "soil_conductivity",
    "max_water_content", "sand_frac", "silt_frac", "clay_frac",
    "carbonate_rocks_frac", "geol_permeability",
]
WARMUP_START, EVAL_END = "1988-10-01", "1999-09-30"


def build() -> None:
    from neuralhydrology.datasetzoo.camelsus import (
        load_camels_us_attributes, load_camels_us_forcings)

    basins = [l.strip().zfill(8) for l in _BASINS_SRC.read_text().splitlines() if l.strip()]
    _BUNDLE.mkdir(parents=True, exist_ok=True)

    # de-couple from xaj: keep a frozen copy of the canonical basin list
    (_FROZEN / "track0_forcing_only_basins.txt").write_text("\n".join(basins) + "\n", encoding="utf-8")

    # forcing (5 Maurer vars, no discharge)
    frames = []
    for b in basins:
        df, _area = load_camels_us_forcings(_DATA, b, "maurer")
        df = df.loc[WARMUP_START:EVAL_END, DYN].copy()
        df.insert(0, "basin", b)
        df.insert(1, "date", df.index)
        frames.append(df.reset_index(drop=True))
    forcing = pd.concat(frames, ignore_index=True)
    forcing.to_parquet(_BUNDLE / "track0_forcing.parquet", index=False)

    # 27 static attributes
    attrs = load_camels_us_attributes(_DATA, basins)[STATIC_27]
    attrs.to_csv(_BUNDLE / "track0_statics.csv")

    (_BUNDLE / "README.txt").write_text(
        "Track-0 ALLOWED inputs only: 5 Maurer forcings + 27 statics, "
        f"{WARMUP_START}..{EVAL_END}. NO observed discharge here — the answer "
        "key is held by the scoring service. Challenger reads ONLY this bundle.\n",
        encoding="utf-8")

    print(f"forcing: {len(forcing)} rows x {len(DYN)} vars, {forcing['basin'].nunique()} basins")
    print(f"statics: {attrs.shape[0]} basins x {attrs.shape[1]} attrs -> {_BUNDLE}")


if __name__ == "__main__":
    build()
