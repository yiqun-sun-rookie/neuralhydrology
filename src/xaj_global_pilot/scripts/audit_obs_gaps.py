"""Audit how many of the 531 basins lose forcing days to obs-NaN dropping
under the default keep_obs_nan_days=False, in the repro_v01 cal/eval windows.

This quantifies the real impact of the 'forcing-gap telescoping' finding before
deciding whether the loader fix changes any result.
"""
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, "src")
from hydroagent.data_loading import load_camels_basin  # noqa: E402
from xaj_global_pilot.config import repro_split_periods  # noqa: E402


def main() -> int:
    per = repro_split_periods()
    windows = {"cal": per["calibration"], "eval": per["evaluation"]}
    manifest = Path("src/xaj_global_pilot/configs/conceptual_benchmark_camels_us_531_repro.txt")
    basins = [l.strip().zfill(8) for l in manifest.read_text().splitlines() if l.strip()]

    cal_gap, eval_gap, errs = [], [], []
    len_diff = []  # basins where len(drop) != len(keep) -> leading/trailing days dropped
    worst = []
    for i, b in enumerate(basins):
        tot = 0
        for lbl, (s, e) in windows.items():
            try:
                fd, _, _ = load_camels_basin(b, data_root="data/camels_us", start_date=s,
                                             end_date=e, forcing="maurer", pet_method="oudin",
                                             keep_obs_nan_days=False)
                fk, _, _ = load_camels_basin(b, data_root="data/camels_us", start_date=s,
                                             end_date=e, forcing="maurer", pet_method="oudin",
                                             keep_obs_nan_days=True)
                d = np.asarray((fd.index[1:] - fd.index[:-1]).days)
                g = int((d[d > 1] - 1).sum())
                tot += g
                if g > 0:
                    (cal_gap if lbl == "cal" else eval_gap).append(b)
                if len(fd) != len(fk):
                    len_diff.append((b, lbl, len(fk) - len(fd)))
            except Exception as ex:  # noqa: BLE001
                errs.append((b, lbl, str(ex)[:50]))
        if tot > 0:
            worst.append((b, tot))
        if (i + 1) % 100 == 0:
            print(f"  ...{i+1}/{len(basins)}", flush=True)

    affected = sorted(set(cal_gap + eval_gap))
    print(f"\n531 obs-gap scan (repro_v01 cal+eval, keep_obs_nan_days=False):")
    print(f"  basins with interior cal gaps : {len(set(cal_gap))}")
    print(f"  basins with interior eval gaps: {len(set(eval_gap))}")
    print(f"  basins with len(drop)!=len(keep) (leading/trailing dropped): {len(len_diff)}")
    print(f"  basins affected total: {len(set(affected) | {b for b,_,_ in len_diff})} / {len(basins)}")
    print(f"  load errors          : {len(errs)}")
    if len_diff:
        print(f"  len-diff detail (first 12): {len_diff[:12]}")
    if worst:
        worst.sort(key=lambda x: -x[1])
        print(f"  worst interior gap_days: {worst[:10]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
