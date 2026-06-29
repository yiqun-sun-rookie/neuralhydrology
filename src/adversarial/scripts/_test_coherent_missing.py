"""Direct-run unit tests for the coherent missing-experiment methods (CPU).

Run: python src/adversarial/scripts/_test_coherent_missing.py

Covers (Tasks 1-4 of docs/plans/2026-06-29-adversarial-id18-missing-experiments.md):
  apgd_targeted(return_kge), apgd_detect (KS), _find_peaks/_pre_event_mask/apgd_causal, cw_min_l2.
Adversarial code is outside test/ (pytest collects only test/), so this runs standalone.
"""
from __future__ import annotations

import sys
from pathlib import Path

import torch

_root = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(_root))
from src.adversarial.scripts.coherent_attack import CoherentBasin  # noqa: E402


class _FakeScalerWrapper:
    """Minimal stand-in for CudaLSTMWrapper: linear model, identity scaler, Maurer temp tie."""

    dynamic_features = ["PRCP", "Tmin", "Tmax", "SRAD", "Vp"]

    class _Cfg:
        target_variables = ["QObs(mm/d)"]

    cfg = _Cfg()

    def __init__(self, F):
        self.F = F
        g = torch.Generator().manual_seed(0)
        self._w = torch.empty(F).uniform_(-1, 1, generator=g)

    def forward(self, x_d, x_s):  # [B,T,F] -> [B,T,1]
        return (x_d * self._w).sum(-1, keepdim=True)

    def get_scaler(self):
        import xarray as xr
        feats = self.dynamic_features + ["QObs(mm/d)"]
        c = xr.Dataset({f: xr.DataArray(0.0) for f in feats})
        s = xr.Dataset({f: xr.DataArray(1.0) for f in feats})
        return {"xarray_feature_center": c, "xarray_feature_scale": s}


def make_fake_basin(N=120, T=20, F=5, seed=1):
    g = torch.Generator().manual_seed(seed)
    x_d = torch.empty(N, T, F).uniform_(-1, 1, generator=g)
    x_d[:, :, 2] = x_d[:, :, 1]                       # Maurer Tmax == Tmin
    x_s = torch.zeros(N, 3)
    w = _FakeScalerWrapper(F)
    # obs = clean preds + noise -> nse_clean < 1 (nonzero residual, so the damage gradient at
    # delta=0 is nonzero, like a real 0.77-NSE basin; a perfect fit would zero the gradient).
    y = w.forward(x_d, x_s) + 0.3 * torch.randn(N, T, 1, generator=g)
    return CoherentBasin(w, x_d, x_s, y, "cpu", chunk=64)


# ---- Task 3: causal-trigger ----
def test_find_peaks_spaced_by_distance():
    cb = make_fake_basin()
    cb.y_last[:] = 0.0
    for p in (20, 50, 90):
        cb.y_last[p] = 10.0
    peaks = cb._find_peaks(p_quantile=0.95, distance=14)
    assert peaks == [20, 50, 90], peaks


def test_pre_event_mask_marks_only_pre_days():
    cb = make_fake_basin()
    m = cb._pre_event_mask([50], pre_window=7)        # [T_cal, F] bool
    cp = 50 + cb.T - 1                                # peak calendar day
    assert m[cp - 7:cp, 0].all()
    assert not m[cp, 0]
    assert not m[cp - 8, 0]


def test_apgd_causal_returns_peak_and_overall():
    cb = make_fake_basin()
    out = cb.apgd_causal(0.2, pre_window=7, n_iter=3)
    assert set(out) >= {"D_peak", "D_overall", "n_peaks"}, set(out)
    assert out["n_peaks"] > 0
    assert out["D_peak"] >= -1e-6                     # damage non-negative (best includes clean)


# ---- Task 1: targeted ΔKGE ----
def test_apgd_targeted_returns_kge_dict_when_requested():
    cb = make_fake_basin()
    out = cb.apgd_targeted(0.1, "untargeted", n_iter=3, return_kge=True)
    assert set(out) >= {"D_nse", "kge_clean", "kge_adv", "dkge"}, set(out)
    assert abs(out["dkge"] - (out["kge_adv"] - out["kge_clean"])) < 1e-6
    d = cb.apgd_targeted(0.1, "untargeted", n_iter=3)  # scalar path unchanged
    assert isinstance(d, float)


# ---- Task 2: KS detectability ----
def test_apgd_detect_reports_ks_per_feature():
    cb = make_fake_basin()
    out = cb.apgd_detect(0.1, n_iter=3)
    assert "D_nse" in out and "ks_p_min" in out
    assert len(out["ks_p"]) == cb.F
    assert 0.0 <= out["ks_p_min"] <= 1.0


# ---- Task 4: C&W minimum L2 (bisection on radius) ----
def test_cw_min_l2_breaks_and_reports_l2():
    cb = make_fake_basin()
    out = cb.cw_min_l2(target_nse=0.0, radius_iters=15, bisect_steps=5, r_hi=20.0)
    assert set(out) >= {"l2", "success", "nse_adv"}, set(out)
    assert out["success"], out                 # a linear fake basin must be breakable within r=20
    assert out["l2"] > 0.0
    assert out["nse_adv"] <= 1e-6              # actually drove NSE below the target


def test_cw_min_l2_unbreakable_reports_failure():
    cb = make_fake_basin()
    out = cb.cw_min_l2(target_nse=0.0, radius_iters=10, bisect_steps=4, r_hi=1e-3)
    assert out["success"] is False             # r_hi too small to break -> honest failure
    assert out["nse_adv"] > 0.0


if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    for fn in fns:
        fn()
        print(f"PASS {fn.__name__}")
    print(f"\nALL {len(fns)} PASSED")
