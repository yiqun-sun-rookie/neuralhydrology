"""Coarse-layer v1: v0 plus forcing spin-up and static region attributes.

Two changes from train_coarse_v0.py, both chosen by ablation in test_input_design.py
and checked for spatial transfer in test_region_transfer.py:

  SPIN-UP. The GRU sequence starts at 1980-01 instead of 2002-01. The loss is still
  scored only on labelled months, so this costs nothing but gives the recurrent state
  22 years of forcing to converge on before the first GRACE month. GRACE storage is
  the running integral of precipitation minus losses, and its memory is long (measured
  optimum: 12 months in humid regions, 30 in arid ones), so a zero initial state at the
  first labelled month throws away information the model needs.

  STATIC ATTRIBUTES. Four region descriptors (annual precipitation, mean warmth, snow,
  radiation) computed from training-period forcing only. One shared network otherwise
  has to apply one average memory length everywhere, which is wrong by a factor of
  three between arid and humid regions.

Rejected after testing: exponential precipitation accumulators (Humphrey-style
pre-integrated precipitation at tau = 3/12/36 months). They help when there is no
spin-up (arid median NSE +0.154) but not with it (+0.033), and once static attributes
are present they hurt (median 0.574 vs 0.602). They are a substitute for the recurrent
integration, not extra information -- worth revisiting only for regions whose forcing
record is too short to spin up.

Measured on the 2011-2014 validation window (3-seed medians, test_input_design.py):
median per-region GRACE NSE 0.495 -> 0.602, arid third 0.123 -> 0.344, regions with
NSE>0 137 -> 143. Seed 0, which is what this script runs, gives 0.602 / 0.288 / 144 and
pooled GRACE NSE 0.587 -> 0.650.

Caveat carried forward from v0: monthly persistence still scores higher on pooled GRACE
NSE (0.817). Persistence needs last month's GRACE, so it cannot be used where the coarse
state is meant to go -- ungauged regions and the pre-2002 record -- but the coarse model
has not yet earned the right to be called a better estimate of storage itself.

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
PRED_OUT = OUT / "coarse_v1_pred.npz"

SPINUP_START = "1980-01-01"  # forcing starts here; labels only from 2002
LABEL_START = "2002-01-01"
TRAIN_END = "2010-12-31"
VAL_START = "2011-01-01"
VAL_END = "2014-12-31"
HIDDEN = 32
EPOCHS = 400
LR = 5e-3
SEED = 0

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


def main() -> None:
    torch.manual_seed(SEED)
    np.random.seed(SEED)

    regions, months, X, feats, Y, targets = load_monthly()
    train_m = (months >= LABEL_START) & (months <= TRAIN_END)
    val_m = (months >= VAL_START) & (months <= VAL_END)
    label_m = months >= LABEL_START

    stat, stat_names = static_attributes(X, feats, train_m)
    X = np.concatenate([X, np.repeat(stat[:, None, :], X.shape[1], axis=1)], axis=-1)
    feat_names = feats + stat_names
    R, T, F = X.shape
    K = len(targets)

    # Features are standardised over every month the model reads before the validation
    # period, spin-up included (1980-2010) -- forcing carries no labels, so nothing leaks
    # and the statistics are more stable. Targets and static attributes use the labelled
    # training window only. This matches the protocol measured in test_input_design.py.
    fstd_m = months <= TRAIN_END
    fmu = np.nanmean(X[:, fstd_m], axis=(0, 1)); fsd = np.nanstd(X[:, fstd_m], axis=(0, 1)) + 1e-6
    Xz = np.nan_to_num((X - fmu) / fsd, nan=0.0)
    tmu = np.array([np.nanmean(Y[:, train_m, k]) for k in range(K)])
    tsd = np.array([np.nanstd(Y[:, train_m, k]) + 1e-6 for k in range(K)])
    Yz = (Y - tmu) / tsd

    dev = "cuda" if torch.cuda.is_available() else "cpu"
    xt = torch.tensor(Xz, dtype=torch.float32, device=dev)
    yt = torch.tensor(Yz, dtype=torch.float32, device=dev)
    mask = torch.tensor(np.isfinite(Yz), dtype=torch.float32, device=dev)
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
    hidden = h_seq.cpu().numpy()  # (R, T, H) learned coarse state, full 1980-2014
    pred = pred_z * tsd + tmu

    # --- baselines, scored on the labelled window only ---
    clim = np.full_like(Y, np.nan)
    cal = months.month
    for k in range(K):
        for mo in range(1, 13):
            tr_sel = train_m & (cal == mo)
            if tr_sel.sum() == 0:
                continue
            clim[:, cal == mo, k] = np.nanmean(Y[:, tr_sel, k], axis=1, keepdims=True)
    persist = np.full_like(Y, np.nan)
    persist[:, 1:, :] = Y[:, :-1, :]

    ann = np.nanmean(X[:, train_m, feats.index("prcp")], axis=1) * 12.0
    q1, q2 = np.nanpercentile(ann, [33.3, 66.7])
    grp = np.where(ann <= q1, 0, np.where(ann <= q2, 1, 2))

    print(f"regions {R}  months {T} ({months.min().date()}..{months.max().date()}); "
          f"spin-up {int((~label_m).sum())} months before the first label")
    print(f"features {F}: {feat_names}")
    print(f"targets {targets}  |  val {VAL_START[:7]}..{VAL_END[:7]} ({int(val_m.sum())} months)  |  device {dev}")
    print(f"{'target':10s} {'model':>8s} {'clim':>8s} {'persist':>8s}   (NSE on val region-months)")
    gi = targets.index("grace_lwe")
    for k, t in enumerate(targets):
        o = Y[:, val_m, k].ravel()
        print(f"{t:10s} {nse(o, pred[:, val_m, k].ravel()):8.3f} "
              f"{nse(o, clim[:, val_m, k].ravel()):8.3f} {nse(o, persist[:, val_m, k].ravel()):8.3f}")

    per = np.array([nse(Y[i, val_m, gi], pred[i, val_m, gi]) for i in range(R)])
    print(f"GRACE per-region val NSE: median {np.nanmedian(per):.3f}   NSE>0 {int(np.nansum(per > 0))}/{R}")
    print(f"  by annual precip: dry(<={q1:.0f} mm) {np.nanmedian(per[grp == 0]):.3f}   "
          f"mid(<={q2:.0f}) {np.nanmedian(per[grp == 1]):.3f}   wet {np.nanmedian(per[grp == 2]):.3f}")

    np.savez(PRED_OUT, regions=np.array(regions), months=months.astype(str).to_numpy(),
             pred=pred, obs=Y, targets=np.array(targets), val_mask=val_m, label_mask=label_m,
             hidden=hidden, feat_names=np.array(feat_names))
    print(f"saved: {PRED_OUT}  (hidden state covers the full {months.min().year}-{months.max().year} axis)")


if __name__ == "__main__":
    main()
