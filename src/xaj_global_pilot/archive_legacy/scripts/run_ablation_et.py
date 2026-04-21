"""消融实验：原版 XAJ (三层蒸发) vs 改版 XAJ (HBV式平滑蒸发)。

在 8 个 humid CAMELS basins 上跑两个版本的 XAJ，
唯一区别是蒸发机制，其余（B 曲线产流 + 三水源 + 三段汇流）完全相同。

用法:
    cd G:/github/pycharm/projects/neuralhydrology
    python -m src.xaj_global_pilot.scripts.run_ablation_et [--trials 5000] [--restarts 3]
"""
import argparse
import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd

# 确保 src 在 path 中
_project_root = Path(__file__).resolve().parents[3]
if str(_project_root) not in sys.path:
    sys.path.insert(0, str(_project_root))
if str(_project_root / "src") not in sys.path:
    sys.path.insert(0, str(_project_root / "src"))

from src.xaj_global_pilot.runner import _load_period, _extract_rain_pet
from src.xaj_global_pilot.config import split_periods
from src.xaj_global_pilot.metrics import compute_metrics
from src.xaj_global_pilot.xaj_model import calibrate_xaj, simulate_xaj, calibrate_xaj_smooth_et
from src.xaj_global_pilot.xaj_numba_smooth_et import simulate_xaj_smooth_et

# 8 humid CAMELS basins（和之前基准测试一致）
BASINS = [
    "01440000", "02011400", "03049000", "04185000",
    "05408000", "06892000", "07057500", "08013000",
]


def run_ablation(n_trials: int = 5000, n_restarts: int = 3) -> pd.DataFrame:
    periods = split_periods()
    rows = []

    for basin_id in BASINS:
        print(f"\n{'='*60}")
        print(f"Basin: {basin_id}")
        print(f"{'='*60}")

        try:
            train_forcing, train_obs = _load_period(basin_id, None, *periods["train"])
            test_forcing, test_obs = _load_period(basin_id, None, *periods["test"])
        except Exception as exc:
            print(f"  [ERROR] 数据加载失败: {exc}")
            for model in ("xaj", "xaj_smooth_et"):
                rows.append({"basin": basin_id, "model": model, "test_nse": np.nan, "error": str(exc)})
            continue

        train_rain, train_pet = _extract_rain_pet(train_forcing)
        test_rain, test_pet = _extract_rain_pet(test_forcing)
        train_obs_arr = train_obs.values.astype(np.float64)

        # --- 原版 XAJ (三层蒸发) ---
        print(f"  Running XAJ (三层蒸发) ... ", end="", flush=True)
        t0 = time.time()
        try:
            result_xaj = calibrate_xaj(train_rain, train_pet, train_obs_arr,
                                       n_trials=n_trials, n_restarts=n_restarts)
            _, final_state = simulate_xaj(train_rain, train_pet, result_xaj['optimized_params'])
            test_q, _ = simulate_xaj(test_rain, test_pet, result_xaj['optimized_params'],
                                     initial_state=final_state)
            test_sim = pd.Series(test_q, index=test_obs.index, name='qsim')
            metrics_xaj = compute_metrics(test_obs, test_sim)
            nse_xaj = metrics_xaj['nse']
            print(f"NSE={nse_xaj:.3f}  ({time.time()-t0:.0f}s)")
            rows.append({"basin": basin_id, "model": "xaj", "test_nse": nse_xaj,
                         **metrics_xaj, "error": ""})
        except Exception as exc:
            print(f"FAILED: {exc}")
            rows.append({"basin": basin_id, "model": "xaj", "test_nse": np.nan, "error": str(exc)})

        # --- 改版 XAJ (HBV式平滑蒸发) ---
        print(f"  Running XAJ-SmoothET (HBV式蒸发) ... ", end="", flush=True)
        t0 = time.time()
        try:
            result_smooth = calibrate_xaj_smooth_et(train_rain, train_pet, train_obs_arr,
                                                    n_trials=n_trials, n_restarts=n_restarts)
            _, final_state = simulate_xaj_smooth_et(train_rain, train_pet, result_smooth['optimized_params'])
            test_q, _ = simulate_xaj_smooth_et(test_rain, test_pet, result_smooth['optimized_params'],
                                               initial_state=final_state)
            test_sim = pd.Series(test_q, index=test_obs.index, name='qsim')
            metrics_smooth = compute_metrics(test_obs, test_sim)
            nse_smooth = metrics_smooth['nse']
            print(f"NSE={nse_smooth:.3f}  ({time.time()-t0:.0f}s)")
            rows.append({"basin": basin_id, "model": "xaj_smooth_et", "test_nse": nse_smooth,
                         **metrics_smooth, "error": ""})
        except Exception as exc:
            print(f"FAILED: {exc}")
            rows.append({"basin": basin_id, "model": "xaj_smooth_et", "test_nse": np.nan, "error": str(exc)})

    df = pd.DataFrame(rows)
    return df


def print_summary(df: pd.DataFrame) -> None:
    print(f"\n{'='*60}")
    print("消融实验结果汇总")
    print(f"{'='*60}")

    pivot = df.pivot(index="basin", columns="model", values="test_nse")
    if "xaj" in pivot.columns and "xaj_smooth_et" in pivot.columns:
        pivot["delta"] = pivot["xaj_smooth_et"] - pivot["xaj"]
        print(pivot.to_string(float_format="%.3f"))
        print(f"\n中位 XAJ:         {pivot['xaj'].median():.3f}")
        print(f"中位 XAJ-SmoothET: {pivot['xaj_smooth_et'].median():.3f}")
        print(f"中位 delta:        {pivot['delta'].median():.3f}")
    else:
        print(df.to_string())


def main():
    parser = argparse.ArgumentParser(description="XAJ 蒸发消融实验")
    parser.add_argument("--trials", type=int, default=5000, help="CMA-ES 每次重启评估次数")
    parser.add_argument("--restarts", type=int, default=3, help="CMA-ES 重启次数")
    parser.add_argument("--output", type=str, default=None, help="结果 CSV 输出路径")
    args = parser.parse_args()

    df = run_ablation(n_trials=args.trials, n_restarts=args.restarts)

    if args.output:
        outpath = Path(args.output)
        outpath.parent.mkdir(parents=True, exist_ok=True)
        df.to_csv(outpath, index=False)
        print(f"\n结果已保存至: {outpath}")

    print_summary(df)


if __name__ == "__main__":
    main()
