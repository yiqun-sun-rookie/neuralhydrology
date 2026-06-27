"""Adapter: materialize GR4J-PDD daily hydrographs from its stored FINAL params.

The conceptual benchmark stores per-basin calibrated params + score, NOT daily
hydrographs. To run GR4J as a fair_benchmark challenger we forward-run it (no
re-calibration) with the locked params: warmup-year init, then simulate over the
eval window, exactly mirroring run_gr4j_pdd_cma_repro_v01._run_one (lines 112-136).
Output: a long predictions CSV (basin,date,qsim) in mm/d.

Run from repo root:
    python -m fair_benchmark.adapters.build_gr4j_predictions --n 40 --out runs/gr4j_pred.csv
"""
import argparse
import sys
from pathlib import Path

import numpy as np
import pandas as pd

_REPO = Path(__file__).resolve().parents[3]
_FINAL = _REPO / "results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/gr4j_pdd_cma_FINAL_pt_v1"
_MANIFEST = _REPO / "src/xaj_global_pilot/configs/conceptual_benchmark_camels_us_531_repro.txt"


def _extract(forcing_df):
    rain = forcing_df["prcp"].to_numpy(dtype=np.float64)
    pet_col = "ep" if "ep" in forcing_df.columns else "pet"
    pet = forcing_df[pet_col].to_numpy(dtype=np.float64)
    temp = (forcing_df["tmean"].to_numpy(dtype=np.float64)
            if "tmean" in forcing_df.columns else np.zeros_like(rain))
    return (np.nan_to_num(rain), np.nan_to_num(pet), np.nan_to_num(temp))


def build(n: int, out_csv: str, data_root: str = "data/camels_us") -> None:
    if str(_REPO / "src") not in sys.path:
        sys.path.insert(0, str(_REPO / "src"))
    from hydroagent.data_loading import load_camels_basin
    from xaj_global_pilot.gr4j_model import simulate_pdd_gr4j
    from xaj_global_pilot.gr4j_core import PDD_GR4J_PARAM_NAMES
    from xaj_global_pilot import config as C
    from fair_benchmark.metrics import nse

    eval_start, eval_end = C.REPRO_EVALUATION_START_DATE, C.REPRO_EVALUATION_END_DATE
    w_start = (pd.Timestamp(eval_start) - pd.DateOffset(years=1)).strftime("%Y-%m-%d")
    w_end = (pd.Timestamp(eval_start) - pd.DateOffset(days=1)).strftime("%Y-%m-%d")
    forcing, pet_method = C.REPRO_FORCING, "priestley_taylor"

    basins = [l.strip().zfill(8) for l in _MANIFEST.read_text().splitlines() if l.strip()][:n]
    pred_rows, native_nse = [], {}
    for b in basins:
        row = pd.read_csv(_FINAL / f"{b}.csv", keep_default_na=False).iloc[0]
        if row.get("run_status") != "success":
            continue
        params = {p: float(row[f"p_{p}"]) for p in PDD_GR4J_PARAM_NAMES}

        fw, _, _ = load_camels_basin(b, data_root=data_root, start_date=w_start,
                                     end_date=w_end, forcing=forcing,
                                     pet_method=pet_method, keep_obs_nan_days=True)
        _, init_state = simulate_pdd_gr4j(*_extract(fw), params, initial_state=None)

        fe, obs_eval, _ = load_camels_basin(b, data_root=data_root, start_date=eval_start,
                                            end_date=eval_end, forcing=forcing,
                                            pet_method=pet_method, keep_obs_nan_days=True)
        q, _ = simulate_pdd_gr4j(*_extract(fe), params, initial_state=init_state)
        sim = pd.Series(q, index=obs_eval.index, name="qsim")

        native_nse[b] = nse(obs_eval, sim)  # vs GR4J's own (area_gages2) obs
        for d, v in zip(sim.index, sim.to_numpy()):
            pred_rows.append({"basin": b, "date": pd.Timestamp(d).strftime("%Y-%m-%d"), "qsim": v})

    out = Path(out_csv)
    out.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(pred_rows).to_csv(out, index=False)
    med = float(np.nanmedian(list(native_nse.values())))
    print(f"wrote {len(pred_rows)} rows for {len(native_nse)} basins -> {out}")
    print(f"GR4J native median NSE (vs own obs) over subset = {med:.4f}")
    pd.Series(native_nse, name="native_nse").to_csv(out.with_suffix(".native_nse.csv"))


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--n", type=int, default=40)
    p.add_argument("--out", default="runs/gr4j_pred.csv")
    p.add_argument("--data-root", default="data/camels_us")
    a = p.parse_args()
    build(n=a.n, out_csv=a.out, data_root=a.data_root)
