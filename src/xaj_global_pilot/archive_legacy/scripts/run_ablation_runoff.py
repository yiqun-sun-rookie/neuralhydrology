"""消融实验 2：原版 XAJ (B曲线) vs XAJ-PowerRunoff (HBV式幂律产流)。

在 8 个 humid CAMELS basins 上对比，唯一区别是产流机制。

用法:
    cd G:/github/pycharm/projects/neuralhydrology
    python -m src.xaj_global_pilot.scripts.run_ablation_runoff [--trials 5000] [--restarts 3]
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

from src.xaj_global_pilot.runner import _load_period, _extract_rain_pet
from src.xaj_global_pilot.config import split_periods
from src.xaj_global_pilot.metrics import compute_metrics
from src.xaj_global_pilot.xaj_model import calibrate_xaj, simulate_xaj, calibrate_xaj_power_runoff
from src.xaj_global_pilot.xaj_numba_power_runoff import simulate_xaj_power_runoff

BASINS = [
    "01440000", "02011400", "03049000", "04185000",
    "05408000", "06892000", "07057500", "08013000",
]


def _run_one(basin_id, model_name, calibrate_fn, simulate_fn, train_rain, train_pet,
             train_obs_arr, test_rain, test_pet, test_obs, n_trials, n_restarts):
    """跑单个模型，返回 (metrics_dict, elapsed_sec)。"""
    t0 = time.time()
    result = calibrate_fn(train_rain, train_pet, train_obs_arr,
                          n_trials=n_trials, n_restarts=n_restarts)
    best_params = result.get('optimized_params')
    if best_params is None:
        raise RuntimeError(f"{model_name} calibration returned no parameters")

    _, final_state = simulate_fn(train_rain, train_pet, best_params)
    test_q, _ = simulate_fn(test_rain, test_pet, best_params, initial_state=final_state)
    test_sim = pd.Series(test_q, index=test_obs.index, name='qsim')
    metrics = compute_metrics(test_obs, test_sim)
    elapsed = time.time() - t0
    return metrics, elapsed


def run_ablation(n_trials: int = 5000, n_restarts: int = 3) -> pd.DataFrame:
    periods = split_periods()
    rows = []

    models = [
        ("xaj", calibrate_xaj, simulate_xaj),
        ("xaj_power_runoff", calibrate_xaj_power_runoff, simulate_xaj_power_runoff),
    ]

    for basin_id in BASINS:
        print(f"\n{'='*60}")
        print(f"Basin: {basin_id}")
        print(f"{'='*60}")

        try:
            train_forcing, train_obs = _load_period(basin_id, None, *periods["train"])
            test_forcing, test_obs = _load_period(basin_id, None, *periods["test"])
        except Exception as exc:
            print(f"  [ERROR] 数据加载失败: {exc}")
            for name, _, _ in models:
                rows.append({"basin": basin_id, "model": name, "test_nse": np.nan, "error": str(exc)})
            continue

        train_rain, train_pet = _extract_rain_pet(train_forcing)
        test_rain, test_pet = _extract_rain_pet(test_forcing)
        train_obs_arr = train_obs.values.astype(np.float64)

        for model_name, cal_fn, sim_fn in models:
            print(f"  Running {model_name} ... ", end="", flush=True)
            try:
                metrics, elapsed = _run_one(
                    basin_id, model_name, cal_fn, sim_fn,
                    train_rain, train_pet, train_obs_arr,
                    test_rain, test_pet, test_obs,
                    n_trials, n_restarts,
                )
                print(f"NSE={metrics['nse']:.3f}  ({elapsed:.0f}s)")
                rows.append({"basin": basin_id, "model": model_name,
                             "test_nse": metrics['nse'], **metrics, "error": ""})
            except Exception as exc:
                print(f"FAILED: {exc}")
                rows.append({"basin": basin_id, "model": model_name,
                             "test_nse": np.nan, "error": str(exc)})

    return pd.DataFrame(rows)


def print_summary(df: pd.DataFrame) -> None:
    print(f"\n{'='*60}")
    print("消融实验 2 结果汇总: B曲线 vs HBV式幂律产流")
    print(f"{'='*60}")

    pivot = df.pivot(index="basin", columns="model", values="test_nse")
    if "xaj" in pivot.columns and "xaj_power_runoff" in pivot.columns:
        pivot["delta"] = pivot["xaj_power_runoff"] - pivot["xaj"]
        print(pivot.to_string(float_format="%.3f"))
        print(f"\n中位 XAJ (B曲线):     {pivot['xaj'].median():.3f}")
        print(f"中位 XAJ-PowerRunoff: {pivot['xaj_power_runoff'].median():.3f}")
        print(f"中位 delta:           {pivot['delta'].median():.3f}")
    else:
        print(df.to_string())


def main():
    parser = argparse.ArgumentParser(description="XAJ 产流机制消融实验")
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
