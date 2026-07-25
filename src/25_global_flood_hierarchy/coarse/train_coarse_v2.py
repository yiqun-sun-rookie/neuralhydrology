"""Coarse-layer v2: v1 plus per-region target standardisation (Step 1.1, zero download).

The one change from train_coarse_v1.py. Everything else -- spin-up, four static
attributes, HIDDEN=32, EPOCHS=400, LR=5e-3, the feature set, the temporal split --
is identical, so this run isolates the effect of the loss weighting alone.

WHY. v1 standardises each target with a SINGLE global scale (one mean and one std
per target, pooled over all regions and all training months). Raw per-region GRACE
std spans 1.59 to 22.37 cm (14x); under one global scale that is a ~200x spread in
squared error, so the masked-MSE loss is dominated by the high-amplitude humid
regions and the arid third is effectively unweighted. v2 standardises each target
PER REGION: every region's labelled training months are scaled to zero mean / unit
variance, so the loss weights every region equally regardless of storage amplitude.
This is the NSE-loss idea (Kratzert et al. 2019) applied at the tile level. The
statistics come from the training window only and are re-applied at prediction time,
so nothing leaks.

DECISION CRITERION (Step 1.1). v1 three-seed medians are median 0.602, arid third
0.344, NSE>0 143/180 (train_coarse_v1.py docstring). Seed 0 alone gives 0.602 /
0.288 / 144. This script runs seeds 0,1,2 and reports the three-seed median. The
loss fix passes if the arid third rises to >= 0.45 (a +0.106 move over the 0.344
baseline, comfortably above the measured 0.073 seed noise) without collapsing the
overall median. If it passes, the next step is capacity (HIDDEN 32->128 + dropout);
if not, the ~200x-weight diagnosis was wrong and the arid weakness is elsewhere.

Temporal split: train 2002-2010, validate 2011-2014.
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd
import torch
import xarray as xr
from torch import nn

REPO = Path(__file__).resolve().parents[3]
OUT = REPO / "results" / "25_global_flood_hierarchy" / "coarse_v0"
FORCING = OUT / "region_forcing" / "region_forcing.nc"
LABELS = OUT / "region_labels.nc"
PRED_OUT = OUT / "coarse_v2_pred.npz"

SPINUP_START = "1980-01-01"  # forcing starts here; labels only from 2002
LABEL_START = "2002-01-01"
TRAIN_END = "2010-12-31"
VAL_START = "2011-01-01"
VAL_END = "2014-12-31"
HIDDEN = 32
EPOCHS = 400
LR = 5e-3
SEEDS = [0, 1, 2]  # three-seed median is the reported number for the decision

SUM_VARS = ["prcp"]  # monthly total
MEAN_VARS = ["srad", "swe", "tmax", "tmin", "vp"]  # monthly mean


class CoarseGRU(nn.Module):
    def __init__(self, n_feat: int, hidden: int, n_targets: int) -> None:
        super().__init__()
        self.gru = nn.GRU(n_feat, hidden, batch_first=True)
        self.head = nn.Linear(hidden, n_targets)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        h, _ = self.gru(x)
        return self.head(h)


def nse(obs: np.ndarray, pred: np.ndarray) -> float:
    m = np.isfinite(obs) & np.isfinite(pred)
    if m.sum() < 5:
        return float("nan")
    o, p = obs[m], pred[m]
    denom = np.sum((o - o.mean()) ** 2)
    return float(1.0 - np.sum((o - p) ** 2) / denom) if denom > 0 else float("nan")


def load_monthly() -> tuple[list[str], pd.DatetimeIndex, np.ndarray, list[str], np.ndarray, list[str]]:
    """Region monthly forcing on the full 1980-2014 axis, with labels aligned onto it."""
    ds = xr.open_dataset(FORCING)
    regions = [str(r) for r in ds["region"].values]
    monthly = xr.Dataset()
    for v in SUM_VARS:
        monthly[v] = ds[v].resample(time="MS").sum()
    for v in MEAN_VARS:
        monthly[v] = ds[v].resample(time="MS").mean()
    feats = SUM_VARS + MEAN_VARS
    months = pd.DatetimeIndex(monthly["time"].values)
    months = months[months <= VAL_END]
    sel = np.isin(pd.DatetimeIndex(monthly["time"].values), months)
    X = np.stack([monthly[v].values[:, sel] for v in feats], axis=-1)  # (R, T, F)

    lab = xr.open_dataset(LABELS).reindex(region=regions)
    targets = [t for t in ["grace_lwe", "soil"] if t in lab]
    ltime = pd.DatetimeIndex(lab["time"].values)
    li = ltime.get_indexer(months)  # -1 where the label axis has no such month
    Y = np.full((len(regions), len(months), len(targets)), np.nan)
    have = li >= 0
    for k, t in enumerate(targets):
        Y[:, have, k] = lab[t].values[:, li[have]]
    return regions, months, X, feats, Y, targets


def static_attributes(X: np.ndarray, feats: list[str], train_m: np.ndarray) -> tuple[np.ndarray, list[str]]:
    """Region descriptors from training-period forcing only -- no labels, no leakage."""
    pi, ti, si, ri = (feats.index(v) for v in ("prcp", "tmax", "swe", "srad"))
    stat = np.stack([
        np.log1p(np.nanmean(X[:, train_m, pi], axis=1) * 12.0),   # annual precipitation
        np.nanmean(X[:, train_m, ti], axis=1),                    # warmth
        np.log1p(np.nanmean(X[:, train_m, si], axis=1)),          # snow
        np.nanmean(X[:, train_m, ri], axis=1),                    # radiation / demand
    ], axis=-1)
    return np.nan_to_num(stat), ["st_precip", "st_tmax", "st_swe", "st_srad"]


def per_region_target_stats(Y: np.ndarray, train_m: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Per-region mean/std of each target over its labelled training months.

    Regions with fewer than 5 labelled training months fall back to (0, 1) so they
    contribute nothing pathological; all GRACE regions share the same monthly label
    axis, so in practice every region has ~108 training months.
    """
    R, _, K = Y.shape
    tmu = np.zeros((R, K))
    tsd = np.ones((R, K))
    for i in range(R):
        for k in range(K):
            v = Y[i, train_m, k]
            v = v[np.isfinite(v)]
            if v.size >= 5:
                tmu[i, k] = v.mean()
                tsd[i, k] = v.std() + 1e-6
    return tmu, tsd


def train_one_seed(seed: int, Xz: np.ndarray, Yz: np.ndarray, mask_np: np.ndarray,
                   train_m: np.ndarray, F: int, K: int, dev: str) -> tuple[np.ndarray, np.ndarray]:
    """Train a fresh model for one seed; return standardised predictions and hidden state."""
    torch.manual_seed(seed)
    np.random.seed(seed)
    xt = torch.tensor(Xz, dtype=torch.float32, device=dev)
    yt = torch.tensor(Yz, dtype=torch.float32, device=dev)
    mask = torch.tensor(mask_np, dtype=torch.float32, device=dev)
    ymask = yt.clone(); ymask[mask == 0] = 0.0
    tr = torch.tensor(train_m, device=dev)

    model = CoarseGRU(F, HIDDEN, K).to(dev)
    opt = torch.optim.Adam(model.parameters(), lr=LR)
    for _ in range(EPOCHS):
        opt.zero_grad()
        se = (model(xt) - ymask) ** 2 * mask
        loss = se[:, tr].sum() / mask[:, tr].sum().clamp(min=1)
        loss.backward()
        opt.step()

    model.eval()
    with torch.no_grad():
        h_seq, _ = model.gru(xt)
        pred_z = model.head(h_seq).cpu().numpy()
    return pred_z, h_seq.cpu().numpy()


def main() -> None:
    regions, months, X, feats, Y, targets = load_monthly()
    train_m = (months >= LABEL_START) & (months <= TRAIN_END)
    val_m = (months >= VAL_START) & (months <= VAL_END)
    label_m = months >= LABEL_START

    stat, stat_names = static_attributes(X, feats, train_m)
    X = np.concatenate([X, np.repeat(stat[:, None, :], X.shape[1], axis=1)], axis=-1)
    feat_names = feats + stat_names
    R, T, F = X.shape
    K = len(targets)

    # Forcing standardised globally over every month read before validation (unchanged
    # from v1). Targets standardised PER REGION over the labelled training window -- this
    # is the only change from v1.
    fstd_m = months <= TRAIN_END
    fmu = np.nanmean(X[:, fstd_m], axis=(0, 1)); fsd = np.nanstd(X[:, fstd_m], axis=(0, 1)) + 1e-6
    Xz = np.nan_to_num((X - fmu) / fsd, nan=0.0)
    tmu, tsd = per_region_target_stats(Y, train_m)   # (R, K) each
    Yz = (Y - tmu[:, None, :]) / tsd[:, None, :]
    mask_np = np.isfinite(Yz)

    dev = "cuda" if torch.cuda.is_available() else "cpu"

    # Region grouping by annual precipitation (seed-independent) and seed-independent baselines.
    ann = np.nanmean(X[:, train_m, feats.index("prcp")], axis=1) * 12.0
    q1, q2 = np.nanpercentile(ann, [33.3, 66.7])
    grp = np.where(ann <= q1, 0, np.where(ann <= q2, 1, 2))
    clim = np.full_like(Y, np.nan)
    cal = months.month
    for k in range(K):
        for mo in range(1, 13):
            tr_sel = train_m & (cal == mo)
            if tr_sel.sum():
                clim[:, cal == mo, k] = np.nanmean(Y[:, tr_sel, k], axis=1, keepdims=True)
    persist = np.full_like(Y, np.nan)
    persist[:, 1:, :] = Y[:, :-1, :]

    gi = targets.index("grace_lwe")
    print(f"regions {R}  months {T} ({months.min().date()}..{months.max().date()}); "
          f"spin-up {int((~label_m).sum())} months before the first label")
    print(f"features {F}: {feat_names}   targets {targets}   device {dev}")
    print(f"val {VAL_START[:7]}..{VAL_END[:7]} ({int(val_m.sum())} months)   seeds {SEEDS}\n")

    metrics = {"median": [], "arid": [], "mid": [], "wet": [], "pos": [], "pooled": []}
    pred_seed0 = hidden_seed0 = None
    for seed in SEEDS:
        pred_z, hidden = train_one_seed(seed, Xz, Yz, mask_np, train_m, F, K, dev)
        pred = pred_z * tsd[:, None, :] + tmu[:, None, :]
        per = np.array([nse(Y[i, val_m, gi], pred[i, val_m, gi]) for i in range(R)])
        metrics["median"].append(np.nanmedian(per))
        metrics["arid"].append(np.nanmedian(per[grp == 0]))
        metrics["mid"].append(np.nanmedian(per[grp == 1]))
        metrics["wet"].append(np.nanmedian(per[grp == 2]))
        metrics["pos"].append(int(np.nansum(per > 0)))
        metrics["pooled"].append(nse(Y[:, val_m, gi].ravel(), pred[:, val_m, gi].ravel()))
        print(f"seed {seed}:  median {metrics['median'][-1]:.3f}   "
              f"arid {metrics['arid'][-1]:.3f}   mid {metrics['mid'][-1]:.3f}   "
              f"wet {metrics['wet'][-1]:.3f}   NSE>0 {metrics['pos'][-1]}/{R}   "
              f"pooled {metrics['pooled'][-1]:.3f}")
        if seed == SEEDS[0]:
            pred_seed0, hidden_seed0 = pred, hidden

    med = {kk: float(np.median(vv)) for kk, vv in metrics.items()}
    print(f"\n3-seed median:  median {med['median']:.3f}   arid {med['arid']:.3f}   "
          f"mid {med['mid']:.3f}   wet {med['wet']:.3f}   NSE>0 {med['pos']:.0f}/{R}   "
          f"pooled {med['pooled']:.3f}")

    # Baselines on the validation window (seed-independent), GRACE only.
    o = Y[:, val_m, gi].ravel()
    print(f"baselines (GRACE, val, pooled):  climatology {nse(o, clim[:, val_m, gi].ravel()):.3f}   "
          f"last-month {nse(o, persist[:, val_m, gi].ravel()):.3f}")

    v1_arid, v1_med, v1_pos = 0.344, 0.602, 143
    print("\n--- Step 1.1 decision (vs v1 3-seed baseline) ---")
    print(f"  arid third: v1 {v1_arid:.3f} -> v2 {med['arid']:.3f} "
          f"(delta {med['arid'] - v1_arid:+.3f}; pass line >= 0.45)")
    print(f"  overall median: v1 {v1_med:.3f} -> v2 {med['median']:.3f} "
          f"(delta {med['median'] - v1_med:+.3f}; must not collapse)")
    print(f"  NSE>0: v1 {v1_pos} -> v2 {med['pos']:.0f}/{R}")
    verdict = "PASS" if (med["arid"] >= 0.45 and med["median"] >= v1_med - 0.073) else "FAIL"
    print(f"  VERDICT: {verdict}")

    np.savez(PRED_OUT, regions=np.array(regions), months=months.astype(str).to_numpy(),
             pred=pred_seed0, obs=Y, targets=np.array(targets), val_mask=val_m, label_mask=label_m,
             hidden=hidden_seed0, feat_names=np.array(feat_names),
             seed_metrics=np.array([metrics[kk] for kk in ["median", "arid", "mid", "wet", "pos", "pooled"]]))
    print(f"\nsaved: {PRED_OUT}  (seed-{SEEDS[0]} pred + hidden, full {months.min().year}-{months.max().year} axis)")


if __name__ == "__main__":
    main()
