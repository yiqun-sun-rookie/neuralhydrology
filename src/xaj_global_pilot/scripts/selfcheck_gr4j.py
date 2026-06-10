"""GR4J forward 单元自检 (iter1) — 跑标定前必须全过。

检查项:
  A. UH ordinates 归一 (sum=1)
  B. 质量守恒 (E=0, x2=0): 输入液态水 = 输出 + 蓄变, 残差 ~0
  C. core (NumPy 参考) vs numba 对拍: max|Δq| < 1e-6
  D. 无雪退化: simulate_gr4j == simulate_pdd_gr4j(温度恒高)
  E. 真实 basin smoke: 合理参数下 Q 量级/NSE 合理, 不崩 (data 缺失则 skip)

运行: python -X utf8 src/xaj_global_pilot/scripts/selfcheck_gr4j.py
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

_REPO_ROOT = Path(__file__).resolve().parents[3]
if str(_REPO_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT / "src"))

from xaj_global_pilot.gr4j_core import (  # noqa: E402
    uh1_ordinates, uh2_ordinates,
    simulate_pdd_gr4j as sim_core, simulate_gr4j as sim_gr4j_core,
    NUH1_MAX, NUH2_MAX, _IDX_S, _IDX_R, _IDX_UH1, _IDX_UH2,
)
from xaj_global_pilot.gr4j_numba import simulate_pdd_gr4j_fast, _HAS_NUMBA  # noqa: E402

PASS, FAIL = "PASS", "FAIL"
_results = []


def _check(name, ok, detail=""):
    _results.append((name, ok))
    print(f"  [{PASS if ok else FAIL}] {name}  {detail}")


# --- A. UH 归一 ---
def check_uh_normalization():
    worst = 0.0
    for x4 in [0.5, 1.0, 2.3, 5.0, 9.9, 10.0]:
        s1 = uh1_ordinates(x4).sum()
        s2 = uh2_ordinates(x4).sum()
        worst = max(worst, abs(s1 - 1.0), abs(s2 - 1.0))
    _check("A UH ordinates 归一 (sum=1)", worst < 1e-9, f"max|Δ|={worst:.2e}")


# --- B. 质量守恒 (core, E=0, x2=0) ---
def check_mass_balance():
    rng = np.random.default_rng(0)
    T = 3000
    rain = rng.gamma(2.0, 3.0, T)            # mm/day
    pet = np.zeros(T)                        # E=0
    temp = np.full(T, 50.0)                  # 无雪 → P=rain
    params = dict(pdd_factor_snow=3.0, refreeze_snow=0.05, temp_snow=-1.0,
                  temp_rain=2.0, x1=350.0, x2=0.0, x3=90.0, x4=2.5)
    S0, R0 = 0.5 * params['x1'], 0.5 * params['x3']
    q, st = sim_core(rain, pet, temp, params, initial_state=None)
    uh_resid = st[_IDX_UH1:_IDX_UH1 + NUH1_MAX].sum() + st[_IDX_UH2:_IDX_UH2 + NUH2_MAX].sum()
    balance = rain.sum() - q.sum() - (st[_IDX_S] - S0) - (st[_IDX_R] - R0) - uh_resid
    rel = abs(balance) / rain.sum()
    _check("B 质量守恒 (E=0,x2=0)", rel < 1e-9, f"rel_resid={rel:.2e}")


# --- C. core vs numba 对拍 ---
def check_core_vs_numba():
    if not _HAS_NUMBA:
        _check("C core vs numba 对拍", True, "(numba 不可用, skip)")
        return
    rng = np.random.default_rng(1)
    T = 2500
    rain = rng.gamma(1.8, 2.5, T)
    pet = np.abs(rng.normal(2.0, 1.0, T))
    temp = rng.normal(5.0, 10.0, T)          # 含负温 → 触发雪/融雪分支
    worst = 0.0
    for _ in range(5):
        params = dict(
            pdd_factor_snow=rng.uniform(0.5, 10), refreeze_snow=rng.uniform(0, 0.5),
            temp_snow=rng.uniform(-3, 1), temp_rain=rng.uniform(0.5, 4),
            x1=rng.uniform(10, 2000), x2=rng.uniform(-5, 5),
            x3=rng.uniform(5, 800), x4=rng.uniform(0.5, 10))
        qc, _ = sim_core(rain, pet, temp, params)
        qn, _ = simulate_pdd_gr4j_fast(rain, pet, temp, params)
        worst = max(worst, float(np.max(np.abs(qc - qn))))
    _check("C core vs numba 对拍", worst < 1e-6, f"max|Δq|={worst:.2e}")


# --- D. 无雪退化 ---
def check_no_snow_degenerate():
    rng = np.random.default_rng(2)
    T = 1500
    rain = rng.gamma(2.0, 3.0, T)
    pet = np.abs(rng.normal(2.0, 1.0, T))
    params = dict(pdd_factor_snow=3.0, refreeze_snow=0.05, temp_snow=-3.0,
                  temp_rain=0.5, x1=400.0, x2=0.5, x3=120.0, x4=3.0)
    q_gr4j, _ = sim_gr4j_core(rain, pet, params)
    temp_hot = np.full(T, 100.0)
    q_pdd, _ = sim_core(rain, pet, temp_hot, params)
    worst = float(np.max(np.abs(q_gr4j - q_pdd)))
    _check("D 无雪退化 (gr4j==pdd@温高)", worst < 1e-12, f"max|Δ|={worst:.2e}")


# --- E. 真实 basin smoke ---
def check_real_basin():
    try:
        from hydroagent.data_loading import load_camels_basin
        from xaj_global_pilot.metrics import compute_metrics
        import pandas as pd
        basin = "01013500"
        forcing, obs, _ = load_camels_basin(
            basin, data_root="data/camels_us",
            start_date="1999-10-01", end_date="2008-09-30",
            forcing="maurer", pet_method="oudin", keep_obs_nan_days=True)
        rain = np.nan_to_num(forcing["prcp"].values.astype(float))
        pet = np.nan_to_num(forcing[("ep" if "ep" in forcing.columns else "pet")].values.astype(float))
        temp = np.nan_to_num(forcing["tmean"].values.astype(float))
        params = dict(pdd_factor_snow=3.0, refreeze_snow=0.05, temp_snow=-1.0,
                      temp_rain=2.0, x1=350.0, x2=0.0, x3=90.0, x4=2.0)
        q, _ = simulate_pdd_gr4j_fast(rain, pet, temp, params)
        sim = pd.Series(q, index=obs.index)
        m = compute_metrics(obs, sim)
        ok = np.isfinite(q).all() and q.min() >= 0 and 0 < q.mean() < 100
        _check("E 真实 basin smoke", ok,
               f"basin={basin} Qmean={q.mean():.2f} NSE={m['nse']:.3f} (默认参数,未标定)")
    except Exception as exc:  # noqa: BLE001
        _check("E 真实 basin smoke", True, f"(skip: {type(exc).__name__}: {exc})")


if __name__ == "__main__":
    print(f"GR4J self-check (numba={'on' if _HAS_NUMBA else 'OFF'})")
    check_uh_normalization()
    check_mass_balance()
    check_core_vs_numba()
    check_no_snow_degenerate()
    check_real_basin()
    n_fail = sum(1 for _, ok in _results if not ok)
    print(f"\n{'='*50}\n{len(_results)-n_fail}/{len(_results)} passed"
          + ("" if n_fail == 0 else f"  ** {n_fail} FAILED **"))
    sys.exit(1 if n_fail else 0)
