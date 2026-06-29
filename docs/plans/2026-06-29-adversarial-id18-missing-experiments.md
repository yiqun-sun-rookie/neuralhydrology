# Adversarial ID18 Missing-Experiments + Manuscript Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run the four manuscript experiments that have no ID18 data yet (targeted-ΔKGE, KS detectability, causal-trigger/pre-event, C&W minimum-perturbation) on the coherent ID18 pipeline, then fully rewrite `main.tex` to the audited ID18 numbers with all honest-boundary fixes and regenerated figures.

**Architecture:** Extend the existing `CoherentBasin` driver (`src/adversarial/scripts/coherent_attack.py`) with four new attack/metric methods, each reusing its shared-delta `unfold` windowing and last-step NSE (which matches the official RegressionTester to 2.6e-7). One runner per experiment writes a per-basin JSON to `results/05_adversarial_robustness/id18_s100/`. Pure logic (peak finding, masking, KS, C&W bookkeeping) is unit-tested on CPU with a tiny synthetic basin; GPU integration is smoke-tested on 2–3 basins before the full background run. The manuscript rewrite swaps every number to the recomputed ID18 ground truth, drops the un-runnable old framings, and regenerates all five figures from the new JSONs.

**Tech Stack:** Python, PyTorch 2.2.2 (CUDA), NumPy, SciPy (`find_peaks`, `ks_2samp`), Matplotlib, LaTeX (AGU `agujournal2019`). Victim: `results/18_lstm_fair_531/lstm_cudalstm_maurer_s100_2026_0616_1513_ep30` (cudalstm + 27 static, Maurer, reverse split, h256, seq270, predict_last_n=1, test median NSE 0.7332).

---

## Design Decisions (locked here; flagged for review at handoff)

1. **Victim / data**: identical to Exp1–3/6 — ID18 epoch 30, 531 basins (`src/adversarial/data/531_basins.txt`), Maurer forcing, reverse split. `data_dir=data/camels_us` (NEVER `data/camels_us/full`, which has broken lowercase headers).
2. **Calendar-day indexing**: `CoherentBasin` uses `T_cal = N + T - 1`. The last-step prediction of window `g` (0…N−1) lands on calendar day `g + T − 1`. The first `T−1` calendar days are warmup-only.
3. **Exp4 peaks**: detected on the observed last-step series `y_last` (length N, valid days only) via `scipy.signal.find_peaks(height=p95, distance=14)`. Peak window index `p` → peak calendar day `cp = p + T − 1`. Pre-event perturbable set = calendar days `[cp − pre_window, cp)` (clamped ≥0), union over peaks, for `pre_window ∈ {1,3,7,14}`.
4. **Exp4 metric**: APGD restricted to the pre-event calendar-day set, optimizing squared error on the **peak windows** `{p}`. Report **two** numbers per `pre_window`: `D_peak` (degradation of a peak-only NSE, denominator = variance of `y_last` over peak days) and `D_overall` (degradation of the standard all-window last-step NSE). Caveat to disclose: at `pre_window=14` with min peak distance 14, a peak's pre-event window can reach a previous peak day (adjacent, non-overlapping at exactly 14).
5. **Exp5 C&W**: minimize `‖delta_cal‖₂` (standardized units) s.t. last-step NSE < 0, Lagrangian `l2 + c·max(0, nse)`, binary search on `c`. Subset = stride-7 over 531 (≈76 basins) for cost; report per-basin min L2 and success flag.
6. **Temperature tie (F9)** applies to every new attack exactly as in the existing ones: gradient attacks via `_tie_grad` (sign of g1+g2), random/free deltas via `_tie_copy` (copy temp channel 1→2). Maurer Tmax≡Tmin.
7. **Tests location**: adversarial code is outside `test/` (pytest collects only `test/`), so unit tests live in `src/adversarial/scripts/_test_coherent_missing.py`, run directly with `python`. Follows the repo's `_test_*.py` convention.
8. **Honesty rails** (carried into the rewrite, per `draft/papers/05_adversarial_latex/yang2026_related_work_and_plan.md` + the methodology re-verify): headline = median ΔNSE and APGD/**random_sign**(K=100) (NOT Gaussian); delete all self-"first"; Yang only a-fortiori; statistical = whole-test-period moments (approximately preserved; looser than per-window, removes LESS → strengthens "QC insufficient"); no US-vs-DE fragility ranking.

---

## Task 1: Targeted ΔKGE (extend Exp3)

Adds physical-space KGE to the targeted attack so Table 3 can report ΔNSE **and** ΔKGE for untargeted/flood/lowflow.

**Files:**
- Modify: `src/adversarial/scripts/coherent_attack.py` (method `apgd_targeted`, ~line 208)
- Modify: `src/adversarial/scripts/run_exp3.py:42-43`
- Test: `src/adversarial/scripts/_test_coherent_missing.py`

- [ ] **Step 1: Write the failing test** (append to `_test_coherent_missing.py`; see Task 3 Step 1 for the synthetic-basin harness `make_fake_basin()` it depends on — create that first if running tasks out of order)

```python
def test_apgd_targeted_returns_kge_dict_when_requested():
    cb = make_fake_basin()
    out = cb.apgd_targeted(0.1, "untargeted", n_iter=3, return_kge=True)
    assert set(out) >= {"D_nse", "kge_clean", "kge_adv", "dkge"}
    assert out["dkge"] == out["kge_adv"] - out["kge_clean"]
    # scalar path unchanged (back-compat)
    d = cb.apgd_targeted(0.1, "untargeted", n_iter=3)
    assert isinstance(d, float)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python src/adversarial/scripts/_test_coherent_missing.py`
Expected: FAIL (`apgd_targeted() got an unexpected keyword argument 'return_kge'`)

- [ ] **Step 3: Implement** — replace `apgd_targeted` body to track `best_delta` and optionally return KGE (reuses `_kge_phys`/`_preds` already in the class):

```python
def apgd_targeted(self, eps: float, target: str, n_iter: int = 50, seed: int = 0,
                  return_kge: bool = False):
    """APGD optimizing damage on the target-day subset; reports OVERALL damage
    D=nse_clean-nse_adv. If return_kge, also reports physical-space ΔKGE on the
    same adversary (KGE evaluated over ALL valid days, like Exp6)."""
    tmask = self._flow_mask(target)
    g0 = torch.Generator(device=self.device).manual_seed(seed)
    delta = _clamp(_tie_copy(torch.empty(self.T_cal, self.F, device=self.device).uniform_(-eps, eps, generator=g0)), eps)
    best, best_delta = self.nse(delta), delta
    alpha = 2 * eps
    for t in range(n_iter):
        g = _tie_grad(self._grad_masked(delta, tmask))
        delta = _clamp(delta + alpha * g.sign(), eps)
        cur = self.nse(delta)
        if cur < best:
            best, best_delta = cur, delta
        if t in (int(n_iter * 0.22), int(n_iter * 0.5), int(n_iter * 0.75)):
            alpha *= 0.5
    d_nse = self.nse_clean - best
    if not return_kge:
        return d_nse
    kge_c = self._kge_phys(self._preds(self.zero))
    kge_a = self._kge_phys(self._preds(best_delta))
    return dict(D_nse=d_nse, kge_clean=kge_c, kge_adv=kge_a, dkge=kge_a - kge_c)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python src/adversarial/scripts/_test_coherent_missing.py`
Expected: PASS

- [ ] **Step 5: Update runner** `run_exp3.py` to store KGE — replace lines 42–43:

```python
            for tgt in ["untargeted", "flood", "lowflow"]:
                r = cb.apgd_targeted(args.eps, tgt, n_iter=args.apgd_iters, return_kge=True)
                rec[f"D_{tgt}"] = r["D_nse"]
                rec[f"dkge_{tgt}"] = r["dkge"]
                if tgt == "untargeted":
                    rec["kge_clean"] = r["kge_clean"]
```

- [ ] **Step 6: Smoke run (2 basins, GPU)**

Run: `python src/adversarial/scripts/run_exp3.py --stride 266 --eps 0.1 --apgd-iters 10`
Expected: writes `exp3_targeted.json` with `dkge_untargeted/flood/lowflow` keys; no error rows.

- [ ] **Step 7: Commit**

```bash
git add src/adversarial/scripts/coherent_attack.py src/adversarial/scripts/run_exp3.py src/adversarial/scripts/_test_coherent_missing.py
git commit -m "feat(adv): targeted ΔKGE in apgd_targeted + Exp3 runner"
```

- [ ] **Step 8: Full background run** (107 basins, stride 5 — matches Exp3's existing coverage)

Run (background): `python src/adversarial/scripts/run_exp3.py --stride 5 --eps 0.1`
Expected: ~1 h; final line prints flood/lowflow ratio ≈ 6.7×; `exp3_targeted.json` has 107 records with ΔNSE + ΔKGE.

---

## Task 2: KS Detectability

For the untargeted APGD adversary at ε=0.1, compute a Kolmogorov–Smirnov 2-sample p-value between the clean and perturbed whole-period marginal of each forcing feature, paired with the achieved |ΔNSE|. Drives Figure 5.

**Files:**
- Modify: `src/adversarial/scripts/coherent_attack.py` (new method `apgd_detect`)
- Create: `src/adversarial/scripts/run_exp_detect.py`
- Test: `src/adversarial/scripts/_test_coherent_missing.py`

- [ ] **Step 1: Write the failing test**

```python
def test_apgd_detect_reports_ks_per_feature():
    cb = make_fake_basin()
    out = cb.apgd_detect(0.1, n_iter=3)
    assert "D_nse" in out and "ks_p_min" in out
    assert len(out["ks_p"]) == cb.F           # one p-value per feature
    assert 0.0 <= out["ks_p_min"] <= 1.0
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python src/adversarial/scripts/_test_coherent_missing.py`
Expected: FAIL (`'CoherentBasin' object has no attribute 'apgd_detect'`)

- [ ] **Step 3: Implement** — add after `apgd_kge`. Reuses the untargeted APGD loop, then KS on `clean_cal` vs `clean_cal + best_delta` per feature:

```python
def apgd_detect(self, eps: float, n_iter: int = 50, seed: int = 0) -> dict:
    """Untargeted APGD at eps; returns ΔNSE and a per-feature KS 2-sample p-value
    between the clean and perturbed WHOLE-period marginal (detectability)."""
    from scipy.stats import ks_2samp
    g0 = torch.Generator(device=self.device).manual_seed(seed)
    delta = _clamp(_tie_copy(torch.empty(self.T_cal, self.F, device=self.device).uniform_(-eps, eps, generator=g0)), eps)
    best, best_delta = self.nse(delta), delta
    alpha = 2 * eps
    for t in range(n_iter):
        g = _tie_grad(self.grad(delta))
        delta = _clamp(delta + alpha * g.sign(), eps)
        cur = self.nse(delta)
        if cur < best:
            best, best_delta = cur, delta
        if t in (int(n_iter * 0.22), int(n_iter * 0.5), int(n_iter * 0.75)):
            alpha *= 0.5
    clean = self.clean_cal.detach().cpu().numpy()
    adv = (self.clean_cal + best_delta).detach().cpu().numpy()
    ks_p = [float(ks_2samp(clean[:, f], adv[:, f]).pvalue) for f in range(self.F)]
    return dict(D_nse=self.nse_clean - best, nse_adv=best,
                ks_p=ks_p, ks_p_min=min(ks_p))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python src/adversarial/scripts/_test_coherent_missing.py`
Expected: PASS

- [ ] **Step 5: Create runner** `run_exp_detect.py` (clone `run_exp6.py`, swap call + output):

```python
"""KS detectability: untargeted APGD @ eps=0.1, per-feature KS p vs |ΔNSE| (Fig 5)."""
from __future__ import annotations
import argparse, json, pickle, sys, time
from pathlib import Path
import torch

_root = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(_root))
from src.adversarial.model_wrapper import CudaLSTMWrapper  # noqa: E402
from src.adversarial.data_loader import load_basin_data  # noqa: E402
from src.adversarial.scripts.coherent_attack import CoherentBasin  # noqa: E402

RUN_DIR = _root / "results/18_lstm_fair_531/lstm_cudalstm_maurer_s100_2026_0616_1513_ep30"
BASIN_FILE = _root / "src/adversarial/data/531_basins.txt"
OUT = _root / "results/05_adversarial_robustness/id18_s100/exp_detect.json"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stride", type=int, default=5)
    ap.add_argument("--eps", type=float, default=0.1)
    ap.add_argument("--apgd-iters", type=int, default=50)
    ap.add_argument("--device", default="cuda:0")
    args = ap.parse_args()
    dev = args.device if torch.cuda.is_available() else "cpu"
    basins = [b.strip() for b in open(BASIN_FILE) if b.strip()][:: args.stride]
    wrapper = CudaLSTMWrapper(run_dir=RUN_DIR, device=dev)
    out, t0 = [], time.time()
    for bi, basin in enumerate(basins):
        try:
            x_d, x_s, y_obs = load_basin_data(run_dir=RUN_DIR, basin_id=basin, period="test", device=dev)
            cb = CoherentBasin(wrapper, x_d, x_s, y_obs, dev, chunk=512)
            r = cb.apgd_detect(args.eps, n_iter=args.apgd_iters)
            out.append(dict(basin=basin, nse_clean=cb.nse_clean, **r))
            del cb, x_d, x_s, y_obs
            torch.cuda.empty_cache()
        except Exception as e:  # noqa: BLE001
            out.append(dict(basin=basin, error=str(e)))
            print(f"[{bi}] {basin} ERROR {e}", flush=True)
        json.dump(out, open(OUT, "w"), indent=1)
        print(f"[{bi+1}/{len(basins)}] {basin} | {(time.time()-t0)/(bi+1):.0f}s/basin", flush=True)
    print(f"DONE -> {OUT}", flush=True)


if __name__ == "__main__":
    main()
```

- [ ] **Step 6: Smoke run (2 basins)**

Run: `python src/adversarial/scripts/run_exp_detect.py --stride 266 --eps 0.1 --apgd-iters 10`
Expected: `exp_detect.json` with `ks_p` (len 5), `ks_p_min`, `D_nse` per basin.

- [ ] **Step 7: Commit**

```bash
git add src/adversarial/scripts/coherent_attack.py src/adversarial/scripts/run_exp_detect.py src/adversarial/scripts/_test_coherent_missing.py
git commit -m "feat(adv): KS detectability (apgd_detect) + runner"
```

- [ ] **Step 8: Full background run** (107 basins)

Run (background): `python src/adversarial/scripts/run_exp_detect.py --stride 5 --eps 0.1`

---

## Task 3: Exp4 Causal-Trigger (pre-event) — coherent

**Files:**
- Modify: `src/adversarial/scripts/coherent_attack.py` (new methods `_find_peaks`, `_pre_event_mask`, `apgd_causal`)
- Create: `src/adversarial/scripts/run_exp4.py`
- Test: `src/adversarial/scripts/_test_coherent_missing.py` (incl. the shared `make_fake_basin()` harness)

- [ ] **Step 1: Write the failing tests + synthetic harness** (create the file head if it does not exist yet)

```python
"""Direct-run unit tests for the coherent missing-experiment methods (CPU).
Run: python src/adversarial/scripts/_test_coherent_missing.py
"""
from __future__ import annotations
import sys
from pathlib import Path
import numpy as np
import torch

_root = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(_root))
from src.adversarial.scripts.coherent_attack import CoherentBasin  # noqa: E402


class _FakeScalerWrapper:
    """Minimal stand-in for CudaLSTMWrapper: identity-ish linear model, trivial scaler."""
    dynamic_features = ["PRCP", "Tmin", "Tmax", "SRAD", "Vp"]

    class _Cfg:
        target_variables = ["QObs(mm/d)"]
    cfg = _Cfg()

    def __init__(self, F):
        self.F = F
        g = torch.Generator().manual_seed(0)
        self._w = torch.empty(F, generator=g).uniform_(-1, 1)

    def forward(self, x_d, x_s):           # [B,T,F] -> [B,T,1]
        return (x_d * self._w).sum(-1, keepdim=True)

    def get_scaler(self):
        import xarray as xr
        feats = self.dynamic_features + ["QObs(mm/d)"]
        c = xr.Dataset({f: xr.DataArray(0.0) for f in feats})
        s = xr.Dataset({f: xr.DataArray(1.0) for f in feats})
        return {"xarray_feature_center": c, "xarray_feature_scale": s}


def make_fake_basin(N=120, T=20, F=5, seed=1):
    g = torch.Generator().manual_seed(seed)
    x_d = torch.empty(N, T, F, generator=g).uniform_(-1, 1)
    x_d[:, :, 2] = x_d[:, :, 1]                       # Maurer Tmax==Tmin
    x_s = torch.zeros(N, 3)
    w = _FakeScalerWrapper(F)
    y = w.forward(x_d, x_s)                           # last-step obs = clean preds (so nse_clean≈1)
    return CoherentBasin(w, x_d, x_s, y, "cpu", chunk=64)


def test_find_peaks_spaced_by_distance():
    cb = make_fake_basin()
    # inject 3 clear peaks into y_last with >14 spacing
    cb.y_last[:] = 0.0
    for p in (20, 50, 90):
        cb.y_last[p] = 10.0
    peaks = cb._find_peaks(p_quantile=0.95, distance=14)
    assert peaks == [20, 50, 90]


def test_pre_event_mask_marks_only_pre_days():
    cb = make_fake_basin()
    m = cb._pre_event_mask([50], pre_window=7)        # [T_cal, F] bool
    cp = 50 + cb.T - 1                                # peak calendar day
    assert m[cp - 7:cp, 0].all() and not m[cp, 0] and not m[cp - 8, 0]


def test_apgd_causal_returns_peak_and_overall():
    cb = make_fake_basin()
    out = cb.apgd_causal(0.2, pre_window=7, n_iter=3)
    assert set(out) >= {"D_peak", "D_overall", "n_peaks"}
    assert out["D_peak"] >= -1e-6                     # damage is non-negative (best-of-iters)


# ---- Task 1 / Task 2 tests appended below in their tasks ----

if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for fn in fns:
        fn(); print(f"PASS {fn.__name__}")
    print(f"\nALL {len(fns)} PASSED")
```

- [ ] **Step 2: Run to verify it fails**

Run: `python src/adversarial/scripts/_test_coherent_missing.py`
Expected: FAIL (`'CoherentBasin' object has no attribute '_find_peaks'`)

- [ ] **Step 3: Implement** the three methods (add to `CoherentBasin`):

```python
# --- causal-trigger (Exp4): perturb only pre-event days, damage the peak prediction ---
def _find_peaks(self, p_quantile: float = 0.95, distance: int = 14) -> list:
    """Flood-peak window indices p (0..N-1) on the valid last-step obs series."""
    import numpy as np
    from scipy.signal import find_peaks
    y = self.y_last.detach().cpu().numpy().copy()
    y[~self.mask.cpu().numpy()] = -np.inf
    finite = y[np.isfinite(y)]
    if finite.size == 0:
        return []
    thr = np.quantile(finite, p_quantile)
    peaks, _ = find_peaks(np.nan_to_num(y, neginf=-1e30), height=thr, distance=distance)
    return peaks.tolist()

def _pre_event_mask(self, peaks: list, pre_window: int) -> torch.Tensor:
    """[T_cal, F] bool: True on the pre_window calendar days before each peak day."""
    m = torch.zeros(self.T_cal, self.F, dtype=torch.bool, device=self.device)
    for p in peaks:
        cp = p + self.T - 1                       # peak calendar day
        lo = max(0, cp - pre_window)
        m[lo:cp, :] = True
    return m

def _peak_nse(self, preds: torch.Tensor, peaks: torch.Tensor) -> float:
    yt = self.y_last[peaks]
    yp = preds[peaks]
    sst = ((yt - yt.mean()) ** 2).sum().clamp(min=1e-10)
    return float(1.0 - ((yt - yp) ** 2).sum() / sst)

def apgd_causal(self, eps: float, pre_window: int, n_iter: int = 50, seed: int = 0) -> dict:
    """APGD with delta restricted to pre-event calendar days, optimizing the peak
    windows' squared error. Reports peak-only and overall last-step ΔNSE."""
    peaks_list = [p for p in self._find_peaks() if self.mask[p]]
    if not peaks_list:
        return dict(D_peak=float("nan"), D_overall=float("nan"), n_peaks=0)
    peaks = torch.tensor(peaks_list, device=self.device)
    pmask = self._pre_event_mask(peaks_list, pre_window).float()   # [T_cal,F]
    tmask = torch.zeros(self.N, dtype=torch.bool, device=self.device)
    tmask[peaks] = True                                            # damage measured on peak windows
    peak_nse_clean = self._peak_nse(self._preds(self.zero), peaks)
    g0 = torch.Generator(device=self.device).manual_seed(seed)
    init = torch.empty(self.T_cal, self.F, device=self.device).uniform_(-eps, eps, generator=g0)
    delta = _clamp(_tie_copy(init) * pmask, eps)                   # zero outside pre-event set
    best_pn, best_delta = self._peak_nse(self._preds(delta), peaks), delta
    alpha = 2 * eps
    for t in range(n_iter):
        g = _tie_grad(self._grad_masked(delta, tmask)) * pmask     # restrict gradient to pre-event
        delta = _clamp(delta + alpha * g.sign() * pmask, eps)
        pn = self._peak_nse(self._preds(delta), peaks)
        if pn < best_pn:
            best_pn, best_delta = pn, delta
        if t in (int(n_iter * 0.22), int(n_iter * 0.5), int(n_iter * 0.75)):
            alpha *= 0.5
    return dict(D_peak=peak_nse_clean - best_pn,
                D_overall=self.nse_clean - self.nse(best_delta),
                n_peaks=len(peaks_list))
```

- [ ] **Step 4: Run to verify it passes**

Run: `python src/adversarial/scripts/_test_coherent_missing.py`
Expected: PASS (find_peaks / pre_event_mask / apgd_causal tests green)

- [ ] **Step 5: Create runner** `run_exp4.py` (clone `run_exp3.py`):

```python
"""Exp4 causal-trigger: pre-event-only APGD damaging flood-peak predictions.
Run (background): python src/adversarial/scripts/run_exp4.py --stride 5 --eps 0.1
"""
from __future__ import annotations
import argparse, json, pickle, sys, time
from pathlib import Path
import torch

_root = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(_root))
from src.adversarial.model_wrapper import CudaLSTMWrapper  # noqa: E402
from src.adversarial.data_loader import load_basin_data  # noqa: E402
from src.adversarial.scripts.coherent_attack import CoherentBasin  # noqa: E402

RUN_DIR = _root / "results/18_lstm_fair_531/lstm_cudalstm_maurer_s100_2026_0616_1513_ep30"
BASIN_FILE = _root / "src/adversarial/data/531_basins.txt"
OUT = _root / "results/05_adversarial_robustness/id18_s100/exp4_causal.json"
WINDOWS = [1, 3, 7, 14]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stride", type=int, default=5)
    ap.add_argument("--eps", type=float, default=0.1)
    ap.add_argument("--apgd-iters", type=int, default=50)
    ap.add_argument("--device", default="cuda:0")
    args = ap.parse_args()
    dev = args.device if torch.cuda.is_available() else "cpu"
    basins = [b.strip() for b in open(BASIN_FILE) if b.strip()][:: args.stride]
    wrapper = CudaLSTMWrapper(run_dir=RUN_DIR, device=dev)
    out, t0 = [], time.time()
    for bi, basin in enumerate(basins):
        try:
            x_d, x_s, y_obs = load_basin_data(run_dir=RUN_DIR, basin_id=basin, period="test", device=dev)
            cb = CoherentBasin(wrapper, x_d, x_s, y_obs, dev, chunk=512)
            rec = dict(basin=basin, nse_clean=cb.nse_clean)
            for w in WINDOWS:
                r = cb.apgd_causal(args.eps, pre_window=w, n_iter=args.apgd_iters)
                rec[f"D_peak_{w}"] = r["D_peak"]
                rec[f"D_overall_{w}"] = r["D_overall"]
                rec["n_peaks"] = r["n_peaks"]
            out.append(rec)
            del cb, x_d, x_s, y_obs
            torch.cuda.empty_cache()
        except Exception as e:  # noqa: BLE001
            out.append(dict(basin=basin, error=str(e)))
            print(f"[{bi}] {basin} ERROR {e}", flush=True)
        json.dump(out, open(OUT, "w"), indent=1)
        print(f"[{bi+1}/{len(basins)}] {basin} | {(time.time()-t0)/(bi+1):.0f}s/basin", flush=True)
    import statistics as st
    ok = [r for r in out if "error" not in r and r.get("n_peaks", 0) > 0]
    med = {w: st.median([r[f"D_overall_{w}"] for r in ok]) for w in WINDOWS}
    print(f"\n=== Exp4 (median D_overall over {len(ok)}): "
          + " ".join(f"{w}d={med[w]:.4f}" for w in WINDOWS) + f"\nDONE -> {OUT}", flush=True)


if __name__ == "__main__":
    main()
```

- [ ] **Step 6: Smoke run (3 basins)**

Run: `python src/adversarial/scripts/run_exp4.py --stride 177 --eps 0.1 --apgd-iters 10`
Expected: `exp4_causal.json` with `D_peak_{1,3,7,14}`, `D_overall_{1,3,7,14}`, `n_peaks`; monotone-ish increase with window; no errors.

- [ ] **Step 7: Commit**

```bash
git add src/adversarial/scripts/coherent_attack.py src/adversarial/scripts/run_exp4.py src/adversarial/scripts/_test_coherent_missing.py
git commit -m "feat(adv): Exp4 coherent causal-trigger (pre-event peak attack)"
```

- [ ] **Step 8: Full background run** (107 basins)

Run (background): `python src/adversarial/scripts/run_exp4.py --stride 5 --eps 0.1`
Expected: ~3–4 h (4 windows × APGD-50); final medians printed.

---

## Task 4: Exp5 C&W minimum-perturbation — coherent

**Files:**
- Modify: `src/adversarial/scripts/coherent_attack.py` (new method `cw_min_l2`)
- Create: `src/adversarial/scripts/run_exp5.py`
- Test: `src/adversarial/scripts/_test_coherent_missing.py`

- [ ] **Step 1: Write the failing test**

```python
def test_cw_min_l2_breaks_and_reports_l2():
    cb = make_fake_basin()
    cb.y_last[:] = cb._preds(cb.zero).detach()    # clean nse≈1 so target NSE<0 is reachable only with effort
    out = cb.cw_min_l2(target_nse=0.0, n_iter=40, bs_steps=3, eps_max=5.0)
    assert set(out) >= {"l2", "success", "nse_adv"}
    if out["success"]:
        assert out["l2"] > 0.0
```

- [ ] **Step 2: Run to verify it fails**

Run: `python src/adversarial/scripts/_test_coherent_missing.py`
Expected: FAIL (`no attribute 'cw_min_l2'`)

- [ ] **Step 3: Implement** — coherent C&W on the shared delta (temperature-tied, last-step NSE):

```python
def cw_min_l2(self, target_nse: float = 0.0, n_iter: int = 200, lr: float = 0.05,
              bs_steps: int = 5, eps_max: float = 5.0, seed: int = 0) -> dict:
    """Minimum ‖delta_cal‖₂ (standardized) s.t. last-step NSE < target_nse.
    Lagrangian l2 + c·max(0, nse-target); binary search on c. Differentiable
    forward over ALL windows (no chunking) — fine for the C&W subset."""
    def _full_nse(delta):
        dw = delta.unfold(0, self.T, 1).permute(0, 2, 1)        # [N,T,F]
        yh = self.w.forward(self.X + dw, self.x_s)[:, -1, 0]
        m = self.mask
        return 1.0 - ((self.y_last[m] - yh[m]) ** 2).sum() / self.ss_tot
    best_l2, best_adv_nse, best_delta = float("inf"), float("inf"), None
    eff_nse, eff_delta = float("inf"), None
    c_lo, c_hi, c = 0.0, 10.0, 1.0
    for _ in range(bs_steps):
        w = torch.zeros(self.T_cal, self.F, device=self.device, requires_grad=True)
        opt = torch.optim.Adam([w], lr=lr)
        for _ in range(n_iter):
            opt.zero_grad()
            delta = _tie_copy(torch.tanh(w) * eps_max)
            nse = _full_nse(delta)
            l2 = delta.norm()
            (l2 + c * torch.clamp(nse - target_nse, min=0.0)).backward()
            opt.step()
        with torch.no_grad():
            delta = _tie_copy(torch.tanh(w) * eps_max)
            nse = float(_full_nse(delta)); l2 = float(delta.norm())
        if nse < eff_nse:
            eff_nse, eff_delta = nse, delta
        if nse <= target_nse and l2 < best_l2:
            best_l2, best_adv_nse, best_delta = l2, nse, delta
            c_hi = c
        else:
            c_lo = c
        c = (c_lo + c_hi) / 2.0
    if best_delta is not None:
        return dict(l2=best_l2, success=True, nse_adv=best_adv_nse)
    return dict(l2=float(eff_delta.norm()) if eff_delta is not None else float("nan"),
                success=False, nse_adv=eff_nse)
```

- [ ] **Step 4: Run to verify it passes**

Run: `python src/adversarial/scripts/_test_coherent_missing.py`
Expected: PASS

- [ ] **Step 5: Create runner** `run_exp5.py` (clone `run_exp6.py`; subset stride 7):

```python
"""Exp5 C&W: minimum L2 perturbation to drive last-step NSE below 0 (per-basin safety margin).
Run (background): python src/adversarial/scripts/run_exp5.py --stride 7
"""
from __future__ import annotations
import argparse, json, sys, time
from pathlib import Path
import torch

_root = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(_root))
from src.adversarial.model_wrapper import CudaLSTMWrapper  # noqa: E402
from src.adversarial.data_loader import load_basin_data  # noqa: E402
from src.adversarial.scripts.coherent_attack import CoherentBasin  # noqa: E402

RUN_DIR = _root / "results/18_lstm_fair_531/lstm_cudalstm_maurer_s100_2026_0616_1513_ep30"
BASIN_FILE = _root / "src/adversarial/data/531_basins.txt"
OUT = _root / "results/05_adversarial_robustness/id18_s100/exp5_cw.json"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stride", type=int, default=7)
    ap.add_argument("--iters", type=int, default=200)
    ap.add_argument("--bs-steps", type=int, default=5)
    ap.add_argument("--device", default="cuda:0")
    args = ap.parse_args()
    dev = args.device if torch.cuda.is_available() else "cpu"
    basins = [b.strip() for b in open(BASIN_FILE) if b.strip()][:: args.stride]
    wrapper = CudaLSTMWrapper(run_dir=RUN_DIR, device=dev)
    out, t0 = [], time.time()
    for bi, basin in enumerate(basins):
        try:
            x_d, x_s, y_obs = load_basin_data(run_dir=RUN_DIR, basin_id=basin, period="test", device=dev)
            cb = CoherentBasin(wrapper, x_d, x_s, y_obs, dev, chunk=512)
            r = cb.cw_min_l2(n_iter=args.iters, bs_steps=args.bs_steps)
            out.append(dict(basin=basin, nse_clean=cb.nse_clean, **r))
            del cb, x_d, x_s, y_obs
            torch.cuda.empty_cache()
        except Exception as e:  # noqa: BLE001
            out.append(dict(basin=basin, error=str(e)))
            print(f"[{bi}] {basin} ERROR {e}", flush=True)
        json.dump(out, open(OUT, "w"), indent=1)
        print(f"[{bi+1}/{len(basins)}] {basin} | {(time.time()-t0)/(bi+1):.0f}s/basin", flush=True)
    import statistics as st
    ok = [r for r in out if "error" not in r and r["success"]]
    if ok:
        print(f"\n=== Exp5: {len(ok)} broke; median L2={st.median([r['l2'] for r in ok]):.3f} ===", flush=True)
    print(f"DONE -> {OUT}", flush=True)


if __name__ == "__main__":
    main()
```

- [ ] **Step 6: Smoke run (3 basins)**

Run: `python src/adversarial/scripts/run_exp5.py --stride 177 --iters 50 --bs-steps 3`
Expected: `exp5_cw.json` with `l2`, `success`, `nse_adv` per basin; no error rows.

- [ ] **Step 7: Commit**

```bash
git add src/adversarial/scripts/coherent_attack.py src/adversarial/scripts/run_exp5.py src/adversarial/scripts/_test_coherent_missing.py
git commit -m "feat(adv): Exp5 coherent C&W minimum-L2 safety margin"
```

- [ ] **Step 8: Full background run** (stride 7 ≈ 76 basins)

Run (background): `python src/adversarial/scripts/run_exp5.py --stride 7`

---

## Task 5: Aggregate + verify all ID18 numbers

Single recompute script that prints every manuscript number from the JSONs, so the rewrite cites verified values (no hand-copied numbers).

**Files:**
- Create: `src/adversarial/scripts/aggregate_id18.py`

- [ ] **Step 1: Implement** the aggregator — load `exp1_eps*.json`, `exp2_constraint_ablation.json`, `exp3_targeted.json`, `exp4_causal.json`, `exp5_cw.json`, `exp6_yang_kge.json`, `exp_detect.json`, `ksweep.json`; print, for each: medians, Q25/Q75, APGD/random_sign ratios, %NSE_adv<0, %ΔNSE<−1, 10th/median/90th percentiles (Fig 2), constraint %lp, targeted ΔNSE+ΔKGE, causal D_peak/D_overall by window, C&W median L2 + %broke, KS p vs |ΔNSE| summary, finite-basin count (confirm 531/531).

```python
"""Print every main.tex number from the ID18 result JSONs (single source of truth)."""
from __future__ import annotations
import json, statistics as st
from pathlib import Path
import numpy as np
R = Path(__file__).resolve().parents[3] / "results/05_adversarial_robustness/id18_s100"
def load(n): return json.load(open(R / f"{n}.json"))
def med(x): return float(np.median(x))
# ... print blocks per experiment (Exp1 ratios/percentiles/%below0; Exp2 %lp;
#     Exp3 ΔNSE+ΔKGE; Exp4 D_peak/D_overall by window; Exp5 L2+%broke; Exp6 KGE;
#     detect KS) ...
```

- [ ] **Step 2: Run + capture**

Run: `python src/adversarial/scripts/aggregate_id18.py | tee results/05_adversarial_robustness/id18_s100/AGGREGATE.txt`
Expected: a complete number sheet; sanity-checks reproduce the already-verified Exp1/2/3/6 values (13.15/14.24/15.92/18.54×, 100/97/78, 6.75×, 0.773/−0.155).

- [ ] **Step 3: Commit**

```bash
git add src/adversarial/scripts/aggregate_id18.py
git commit -m "chore(adv): single-source ID18 number aggregator"
```

---

## Task 6: Rewrite `main.tex` to ID18 + regenerate figures

Decompose into reviewable sub-edits. All numbers come from `AGGREGATE.txt` (Task 5). Use the `paper-writing-en` skill for prose, then `wrr-paper-review` for an independent pass.

**Files:**
- Modify: `draft/papers/05_adversarial_latex/main.tex`
- Create: `src/adversarial/scripts/make_paper_figures.py` (regenerates `figures/fig1…fig5` from the JSONs)
- Modify: `draft/papers/05_adversarial_latex/supporting_information.tex` (drop SI Text S3 non-finite-basin section; update run paths to ID18 ep30)

- [ ] **Step 1: Victim/methods** (§2.1, Table `tab:epsilon`): h128→h256; Daymet→Maurer; 14→27 static; epoch20→epoch30; standard split→reverse split (test 1989-10-01…1999-09-30); recompute the ε→physical table with Maurer training-period σ (from the scaler); clean test median NSE 0.7332. Commit.
- [ ] **Step 2: Random baselines** (§2.2.1, Table `tab:methods`): best-of-10→best-of-100; ADD `random_sign` (±ε corner) as the matched-structure baseline and make it the denominator of the headline ratio; keep Gaussian/Mult-bias/Temp-corr as secondary. Commit.
- [ ] **Step 3: Drop the non-finite caveat globally**: 531/531 finite under ID18 → remove "514 finite", "17 non-finite", SI Text S3 reference everywhere (Key Points, abstract, §2.6, §3.1, captions, Caveats). Commit.
- [ ] **Step 4: Table 1 + §3.1 + Fig 1/2** (attack comparison): swap all medians/IQRs to ID18; replace the `APGD/Gauss` row with `APGD/random_sign` = 13.15/14.24/15.92/18.54×; APGD/FGSM = 1.01/1.09/1.27/1.71×; %NSE_adv<0 = 0.6/3.0/15.4/71.8%; %ΔNSE<−1 from aggregate; regenerate `fig1_epsilon_curve` + `fig2_basin_vulnerability` from `exp1_eps*.json`. Headline 17.5×→15.9×. Commit.
- [ ] **Step 5: Table 2 + §3.2** (constraints): medians lp/phys/stat; %lp = 100/97/78 @ε0.1; fix "reduces 53%/−0.193"→ correct ID18 stat retention (~78%); REWRITE the §3.2/§309 mechanism — under whole-period matching, marginal moments are NOT "pinned by construction" (within-window level shifts remain), so describe the constraint as *approximately* whole-period moment-preserving and note it removes LESS than per-window, which *strengthens* "QC insufficient". Commit.
- [ ] **Step 6: Table 3 + §3.3** (targeted): ΔNSE untarg/flood/lowflow = 0.383/0.322/0.048 (flood/lowflow ≈ 6.75×, NOT 16:1); add ΔKGE column from Task 1; fix the "16:1" claim. Commit.
- [ ] **Step 7: Causal §3.3 + Fig 3** (Exp4): report D_peak (headline, operational) and D_overall (share) by window {1,3,7,14}; regenerate `fig3_causal_window`; disclose the pre_window=14 ≥ peak-distance caveat; update Conclusions "fourth finding". Commit.
- [ ] **Step 8: C&W §3.4 + Fig 4 + KS §3.4 + Fig 5** (Exp5 + detect): median min-L2 + %broke from Exp5; regenerate `fig4_cw_perturbation`; KS p vs |ΔNSE| scatter from `exp_detect.json` → `fig5_detectability`. Commit.
- [ ] **Step 9: Discussion §4.1 Yang reconciliation**: rewrite to a-fortiori — our ε=0.1 vs Yang ε=0.2, our APGD vs Yang FGSM, our clean KGE 0.773 vs Yang 0.833, median ΔKGE −0.155 (−20.1% relative) ≥ Yang −0.105 (−12.6%); state "comparable, if anything larger; NOT directly comparable"; DELETE the US-vs-DE "catastrophic failure rare is harder to defend / one in three basins" cross-dataset ranking (line ~299). Remove all self-"first". Commit.
- [ ] **Step 10: Abstract / Key Points / Plain-Language / Conclusions** — propagate the four corrected findings + 15.9× + 531 + h256. Commit.
- [ ] **Step 11: .bib** — add Fre-CW / Imgrund / TSA-STAT / Chen&Zhu borrowed-method cites (per `yang2026_related_work_and_plan.md`). Commit.
- [ ] **Step 12: Independent review** — run `wrr-paper-review` on the rewritten `main.tex`; address findings. Compile (`pdflatex`+`bibtex`) and confirm no undefined refs / overfull boxes from the new tables. Commit.

---

## Self-Review

**Spec coverage** (the 4 missing experiments + rewrite):
- targeted-ΔKGE → Task 1 ✓; KS detectability → Task 2 ✓; causal-trigger/pre-event → Task 3 ✓; C&W → Task 4 ✓; aggregation → Task 5 ✓; full rewrite + 5 figures + honesty fixes → Task 6 ✓.
- Honesty rails (15.9× not 17.5×, 531 not 514, statistical mechanism, US-vs-DE deletion, no "first") → Task 6 Steps 2,3,4,5,9 ✓.

**Placeholder scan:** Task 5 Step 1 and Task 6 Step list intentionally summarize rather than show every print/edit line — they are aggregation/prose tasks whose exact output depends on run results; each names the precise inputs, outputs, and target numbers. All code-bearing method/runner steps (Tasks 1–4) contain complete runnable code.

**Type consistency:** new `CoherentBasin` methods — `apgd_targeted(...,return_kge)`, `apgd_detect`, `_find_peaks`, `_pre_event_mask`, `_peak_nse`, `apgd_causal`, `cw_min_l2` — all reuse existing attributes (`self.X/x_s/N/T/F/T_cal/mask/y_last/ss_tot/zero/clean_cal/nse_clean`, helpers `_tie_grad/_tie_copy/_clamp/_preds/nse/grad/_grad_masked/_kge_phys/_flow_mask`) verified present in `coherent_attack.py`. Runner JSON keys consumed by Task 5/6 match those written by Tasks 1–4.

**Open risk:** Exp4 `_grad_masked` currently divides by `self.ss_tot` (overall denominator) while damage is read via `_peak_nse` (peak denominator) — acceptable because the gradient only needs the *direction* that raises peak ss_res; sign is unaffected by the constant denominator. Confirm in the Task 3 smoke run that `D_peak` increases with `pre_window`.

---

## Compute budget (rough, RTX 4070Ti)

- Task 1 rerun Exp3 (107): ~1 h · Task 2 detect (107): ~1 h · Task 3 Exp4 (107×4 windows): ~3–4 h · Task 4 Exp5 (76, 200×5 iters): ~2–4 h. Total ≈ 7–10 GPU-h, runnable as sequential background jobs.
