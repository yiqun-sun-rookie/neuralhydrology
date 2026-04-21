"""重新跑 HBV 基准：5000 trials × 3 restarts，与消融实验的 XAJ 对齐。

用法:
    cd G:/github/pycharm/projects/neuralhydrology
    python -m src.xaj_global_pilot.scripts.run_hbv_baseline [--trials 5000] [--restarts 3]
"""
import argparse
import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd

_project_root = Path(__file__).resolve().parents[3]
if str(_project_root) not in sys.path:
    sys.path.insert(0, str(_project_root))
if str(_project_root / "src") not in sys.path:
    sys.path.insert(0, str(_project_root / "src"))

from src.xaj_global_pilot.runner import run_single_model_basin

BASINS = [
    "01440000", "02011400", "03049000", "04185000",
    "05408000", "06892000", "07057500", "08013000",
]

# 消融实验中 XAJ 的稳定结果（5000 trials × 3 restarts，两轮一致）
XAJ_REFERENCE = {
    "01440000": 0.826, "02011400": 0.759, "03049000": 0.649, "04185000": 0.679,
    "05408000": 0.310, "06892000": 0.417, "07057500": 0.861, "08013000": 0.516,
}


def main():
    parser = argparse.ArgumentParser(description="HBV 基准重跑")
    parser.add_argument("--trials", type=int, default=5000)
    parser.add_argument("--restarts", type=int, default=3)
    parser.add_argument("--output", type=str, default=None)
    args = parser.parse_args()

    rows = []
    for basin_id in BASINS:
        print(f"\n{'='*60}")
        print(f"Basin: {basin_id}")
        print(f"{'='*60}")

        t0 = time.time()
        print(f"  Running HBV ... ", end="", flush=True)
        result = run_single_model_basin(basin_id, "hbv", calibration_trials=args.trials)
        elapsed = time.time() - t0

        nse = result.get("nse", np.nan)
        status = result.get("run_status", "unknown")
        error = result.get("error_message", "")

        if status == "success":
            print(f"NSE={nse:.3f}  ({elapsed:.0f}s)")
        else:
            print(f"FAILED: {error}  ({elapsed:.0f}s)")

        rows.append({
            "basin": basin_id,
            "hbv_nse": nse,
            "xaj_nse": XAJ_REFERENCE.get(basin_id, np.nan),
            "status": status,
            "error": error,
        })

    df = pd.DataFrame(rows)
    df["delta_hbv_minus_xaj"] = pd.to_numeric(df["hbv_nse"], errors="coerce") - df["xaj_nse"]

    if args.output:
        outpath = Path(args.output)
        outpath.parent.mkdir(parents=True, exist_ok=True)
        df.to_csv(outpath, index=False)
        print(f"\n结果已保存至: {outpath}")

    print(f"\n{'='*60}")
    print("HBV vs XAJ 对比 (同等率定条件: 5000 trials × 3 restarts)")
    print(f"{'='*60}")
    print(df[["basin", "xaj_nse", "hbv_nse", "delta_hbv_minus_xaj", "status"]].to_string(index=False))

    valid = df[df["status"] == "success"]
    if len(valid) > 0:
        xaj_med = valid["xaj_nse"].median()
        hbv_med = pd.to_numeric(valid["hbv_nse"], errors="coerce").median()
        delta_med = valid["delta_hbv_minus_xaj"].median()
        print(f"\n成功流域数: {len(valid)}/{len(df)}")
        print(f"中位 XAJ:   {xaj_med:.3f}")
        print(f"中位 HBV:   {hbv_med:.3f}")
        print(f"中位 delta: {delta_med:+.3f}")


if __name__ == "__main__":
    main()
