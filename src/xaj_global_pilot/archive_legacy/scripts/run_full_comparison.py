"""全模型对比：PDD+XAJ vs NumPy-HBV vs SuperflexPy-HBV vs PyTorch-HBV。

在 8 个 CAMELS basins 上统一对比，所有模型都含融雪模块。

用法:
    cd G:/github/pycharm/projects/neuralhydrology
    python -m src.xaj_global_pilot.scripts.run_full_comparison [--trials 5000] [--restarts 3]
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

from src.xaj_global_pilot.runner import _load_period, _extract_rain_pet_temp
from src.xaj_global_pilot.config import split_periods
from src.xaj_global_pilot.metrics import compute_metrics

# --- Model imports ---
from src.xaj_global_pilot.xaj_model import calibrate_pdd_xaj, simulate_pdd_xaj
from src.hbv_camels_us_531.hbv_model import calibrate_hbv, simulate_hbv
from src.xaj_global_pilot.runner import run_single_model_basin  # SuperflexPy HBV

BASINS = [
    "01440000", "02011400", "03049000", "04185000",
    "05408000", "06892000", "07057500", "08013000",
]


def _run_pdd_xaj(train_rain, train_pet, train_temp, train_obs_arr,
                  test_rain, test_pet, test_temp, test_obs, n_trials, n_restarts):
    result = calibrate_pdd_xaj(train_rain, train_pet, train_temp, train_obs_arr,
                               n_trials=n_trials, n_restarts=n_restarts)
    params = result['optimized_params']
    _, final_state = simulate_pdd_xaj(train_rain, train_pet, train_temp, params)
    test_q, _ = simulate_pdd_xaj(test_rain, test_pet, test_temp, params,
                                  initial_state=final_state)
    test_sim = pd.Series(test_q, index=test_obs.index, name='qsim')
    return compute_metrics(test_obs, test_sim)


def _run_numpy_hbv(train_rain, train_pet, train_temp, train_obs_arr,
                   test_rain, test_pet, test_temp, test_obs, n_trials, n_restarts):
    result = calibrate_hbv(train_rain, train_pet, train_temp, train_obs_arr,
                           n_trials=n_trials, n_restarts=n_restarts)
    params = result['optimized_params']
    _, final_state = simulate_hbv(train_rain, train_pet, train_temp, params)
    test_q, _ = simulate_hbv(test_rain, test_pet, test_temp, params,
                              initial_state=final_state)
    test_sim = pd.Series(test_q, index=test_obs.index, name='qsim')
    return compute_metrics(test_obs, test_sim)


def _run_torch_hbv(train_rain, train_pet, train_temp, train_obs_arr,
                   test_rain, test_pet, test_temp, test_obs, n_epochs, n_restarts):
    from src.scl_hydro.hbv_calibrate_torch import calibrate_hbv_torch
    from src.scl_hydro.hbv_torch import DifferentiableHBV
    import torch

    result = calibrate_hbv_torch(train_rain, train_pet, train_temp, train_obs_arr,
                                 n_epochs=n_epochs, n_restarts=n_restarts)
    params = result['optimized_params']

    # 用 NumPy HBV 跑 test（结构一致，避免 tensor 转换复杂度）
    _, final_state = simulate_hbv(train_rain, train_pet, train_temp, params)
    test_q, _ = simulate_hbv(test_rain, test_pet, test_temp, params,
                              initial_state=final_state)
    test_sim = pd.Series(test_q, index=test_obs.index, name='qsim')
    return compute_metrics(test_obs, test_sim)


def run_comparison(n_trials: int = 5000, n_restarts: int = 3,
                   torch_epochs: int = 300, torch_restarts: int = 5) -> pd.DataFrame:
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
            for model in ("pdd_xaj", "numpy_hbv", "sfpy_hbv", "torch_hbv"):
                rows.append({"basin": basin_id, "model": model, "test_nse": np.nan, "error": str(exc)})
            continue

        train_rain, train_pet, train_temp = _extract_rain_pet_temp(train_forcing)
        test_rain, test_pet, test_temp = _extract_rain_pet_temp(test_forcing)
        train_obs_arr = train_obs.values.astype(np.float64)

        # --- PDD+XAJ (CMA-ES) ---
        print(f"  [1/4] PDD+XAJ (CMA-ES) ... ", end="", flush=True)
        t0 = time.time()
        try:
            m = _run_pdd_xaj(train_rain, train_pet, train_temp, train_obs_arr,
                             test_rain, test_pet, test_temp, test_obs, n_trials, n_restarts)
            print(f"NSE={m['nse']:.3f}  ({time.time()-t0:.0f}s)")
            rows.append({"basin": basin_id, "model": "pdd_xaj", "test_nse": m['nse'],
                         **m, "error": ""})
        except Exception as exc:
            print(f"FAILED: {exc}")
            rows.append({"basin": basin_id, "model": "pdd_xaj", "test_nse": np.nan, "error": str(exc)})

        # --- NumPy HBV (CMA-ES) ---
        print(f"  [2/4] NumPy HBV (CMA-ES) ... ", end="", flush=True)
        t0 = time.time()
        try:
            m = _run_numpy_hbv(train_rain, train_pet, train_temp, train_obs_arr,
                               test_rain, test_pet, test_temp, test_obs, n_trials, n_restarts)
            print(f"NSE={m['nse']:.3f}  ({time.time()-t0:.0f}s)")
            rows.append({"basin": basin_id, "model": "numpy_hbv", "test_nse": m['nse'],
                         **m, "error": ""})
        except Exception as exc:
            print(f"FAILED: {exc}")
            rows.append({"basin": basin_id, "model": "numpy_hbv", "test_nse": np.nan, "error": str(exc)})

        # --- SuperflexPy HBV (Optuna) ---
        print(f"  [3/4] SuperflexPy HBV ... ", end="", flush=True)
        t0 = time.time()
        try:
            result = run_single_model_basin(basin_id, "hbv", calibration_trials=n_trials)
            nse_sfpy = result.get("nse", np.nan)
            status = result.get("run_status", "failed")
            if status == "success":
                print(f"NSE={nse_sfpy:.3f}  ({time.time()-t0:.0f}s)")
                rows.append({"basin": basin_id, "model": "sfpy_hbv", "test_nse": nse_sfpy,
                             "nse": nse_sfpy, "error": ""})
            else:
                print(f"FAILED: {result.get('error_message', '')}")
                rows.append({"basin": basin_id, "model": "sfpy_hbv", "test_nse": np.nan,
                             "error": result.get("error_message", "")})
        except Exception as exc:
            print(f"FAILED: {exc}")
            rows.append({"basin": basin_id, "model": "sfpy_hbv", "test_nse": np.nan, "error": str(exc)})

        # --- PyTorch HBV (Adam) ---
        print(f"  [4/4] PyTorch HBV (Adam) ... ", end="", flush=True)
        t0 = time.time()
        try:
            m = _run_torch_hbv(train_rain, train_pet, train_temp, train_obs_arr,
                               test_rain, test_pet, test_temp, test_obs,
                               torch_epochs, torch_restarts)
            print(f"NSE={m['nse']:.3f}  ({time.time()-t0:.0f}s)")
            rows.append({"basin": basin_id, "model": "torch_hbv", "test_nse": m['nse'],
                         **m, "error": ""})
        except Exception as exc:
            print(f"FAILED: {exc}")
            rows.append({"basin": basin_id, "model": "torch_hbv", "test_nse": np.nan, "error": str(exc)})

    return pd.DataFrame(rows)


def print_summary(df: pd.DataFrame) -> None:
    print(f"\n{'='*70}")
    print("全模型对比汇总")
    print(f"{'='*70}")

    pivot = df.pivot(index="basin", columns="model", values="test_nse")
    col_order = [c for c in ["pdd_xaj", "numpy_hbv", "sfpy_hbv", "torch_hbv"] if c in pivot.columns]
    pivot = pivot[col_order]
    print(pivot.to_string(float_format="%.3f"))

    print(f"\n中位数:")
    for col in col_order:
        valid = pivot[col].dropna()
        if len(valid) > 0:
            print(f"  {col:15s}: {valid.median():.3f}  (n={len(valid)})")


def main():
    parser = argparse.ArgumentParser(description="XAJ vs HBV 全模型对比")
    parser.add_argument("--trials", type=int, default=5000, help="CMA-ES 每次重启评估次数")
    parser.add_argument("--restarts", type=int, default=3, help="CMA-ES 重启次数")
    parser.add_argument("--torch-epochs", type=int, default=300, help="PyTorch Adam 优化步数")
    parser.add_argument("--torch-restarts", type=int, default=5, help="PyTorch 重启次数")
    parser.add_argument("--output", type=str, default=None, help="结果 CSV 输出路径")
    args = parser.parse_args()

    df = run_comparison(n_trials=args.trials, n_restarts=args.restarts,
                        torch_epochs=args.torch_epochs, torch_restarts=args.torch_restarts)

    if args.output:
        outpath = Path(args.output)
        outpath.parent.mkdir(parents=True, exist_ok=True)
        df.to_csv(outpath, index=False)
        print(f"\n结果已保存至: {outpath}")

    print_summary(df)


if __name__ == "__main__":
    main()
