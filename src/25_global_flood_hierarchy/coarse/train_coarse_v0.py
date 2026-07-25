"""Coarse-layer v0: shared GRU over region-mean monthly forcing -> GRACE + soil.

The coarse water-balance state model. One shared GRU runs over each region's monthly
forcing sequence; two masked heads predict the region's GRACE storage anomaly and
TerraClimate soil moisture. The point of v0 is a go/no-go: does a learned recurrent
state beat the trivial climatology and persistence baselines at the coarse targets?
If it cannot beat them, the coarse state carries nothing worth feeding downstream.

Temporal split: train 2002-2010, validate 2011-2014. Skill = Nash-Sutcliffe (NSE)
per target on validation region-months, model vs climatology vs persistence.
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

TRAIN_END = "2010-12-31"
VAL_START = "2011-01-01"
VAL_END = "2014-12-31"
HIDDEN = 32
EPOCHS = 400
LR = 5e-3
SEED = 0

SUM_VARS = ["prcp"]  # monthly total
MEAN_VARS = ["srad", "swe", "tmax", "tmin", "vp"]  # monthly mean


def load_monthly_features() -> tuple[list[str], pd.DatetimeIndex, np.ndarray, list[str]]:
    ds = xr.open_dataset(FORCING)
    regions = [str(r) for r in ds["region"].values]
    monthly = xr.Dataset()
    for v in SUM_VARS:
        monthly[v] = ds[v].resample(time="MS").sum()
    for v in MEAN_VARS:
        monthly[v] = ds[v].resample(time="MS").mean()
    feat_names = SUM_VARS + MEAN_VARS
    time = pd.DatetimeIndex(monthly["time"].values)
    X = np.stack([monthly[v].values for v in feat_names], axis=-1)  # (region, month, feat)
    return regions, time, X, feat_names


def nse(obs: np.ndarray, pred: np.ndarray) -> float:
    m = np.isfinite(obs) & np.isfinite(pred)
    if m.sum() < 5:
        return float("nan")
    o, p = obs[m], pred[m]
    denom = np.sum((o - o.mean()) ** 2)
    return float(1.0 - np.sum((o - p) ** 2) / denom) if denom > 0 else float("nan")


class CoarseGRU(nn.Module):
    def __init__(self, n_feat: int, hidden: int, n_targets: int) -> None:
        super().__init__()
        self.gru = nn.GRU(n_feat, hidden, batch_first=True)
        self.head = nn.Linear(hidden, n_targets)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        h, _ = self.gru(x)
        return self.head(h)


def main() -> None:
    torch.manual_seed(SEED)
    np.random.seed(SEED)

    regions, ftime, X, feat_names = load_monthly_features()
    lab = xr.open_dataset(LABELS).reindex(region=regions)
    targets = [t for t in ["grace_lwe", "soil"] if t in lab]

    # common monthly axis: forcing months that also carry labels, within study window
    ltime = pd.DatetimeIndex(lab["time"].values)
    months = ftime.intersection(ltime)
    months = months[(months >= "2002-01-01") & (months <= VAL_END)]
    fi = ftime.get_indexer(months)
    li = ltime.get_indexer(months)

    X = X[:, fi, :]  # (R, T, F)
    Y = np.stack([lab[t].values[:, li] for t in targets], axis=-1)  # (R, T, K)
    R, T, F = X.shape
    K = len(targets)

    train_m = months <= TRAIN_END
    val_m = (months >= VAL_START) & (months <= VAL_END)

    # standardize features and targets on train months (targets for balanced loss only)
    fmu = np.nanmean(X[:, train_m], axis=(0, 1)); fsd = np.nanstd(X[:, train_m], axis=(0, 1)) + 1e-6
    Xz = (X - fmu) / fsd
    Xz = np.nan_to_num(Xz, nan=0.0)
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
    for ep in range(EPOCHS):
        opt.zero_grad()
        pred = model(xt)
        se = (pred - ymask) ** 2 * mask
        loss = se[:, tr].sum() / mask[:, tr].sum().clamp(min=1)
        loss.backward()
        opt.step()

    model.eval()
    with torch.no_grad():
        h_seq, _ = model.gru(xt)
        pred_z = model.head(h_seq).cpu().numpy()
    hidden = h_seq.cpu().numpy()  # (R, T, H) learned coarse state
    pred = pred_z * tsd + tmu  # back to original units

    # --- baselines ---
    clim = np.full_like(Y, np.nan)
    cal = months.month
    for k in range(K):
        for mo in range(1, 13):
            tr_sel = train_m & (cal == mo)
            if tr_sel.sum() == 0:
                continue
            clim[:, cal == mo, k] = np.nanmean(Y[:, tr_sel, k], axis=1, keepdims=True)
    persist = np.full_like(Y, np.nan)
    persist[:, 1:, :] = Y[:, :-1, :]  # previous month's observation

    print(f"regions {R}  months {T} ({months.min().date()}..{months.max().date()})  feats {feat_names}")
    print(f"targets {targets}  |  val {VAL_START[:7]}..{VAL_END[:7]}  ({int(val_m.sum())} months)")
    print(f"device {dev}")
    print(f"{'target':10s} {'model':>8s} {'clim':>8s} {'persist':>8s}   (NSE on val region-months)")
    for k, t in enumerate(targets):
        o = Y[:, val_m, k].ravel()
        print(f"{t:10s} {nse(o, pred[:, val_m, k].ravel()):8.3f} "
              f"{nse(o, clim[:, val_m, k].ravel()):8.3f} {nse(o, persist[:, val_m, k].ravel()):8.3f}")

    np.savez(OUT / "coarse_v0_pred.npz", regions=np.array(regions), months=months.astype(str).to_numpy(),
             pred=pred, obs=Y, targets=np.array(targets), val_mask=val_m, hidden=hidden)
    print(f"saved: {OUT / 'coarse_v0_pred.npz'}")


if __name__ == "__main__":
    main()
