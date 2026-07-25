"""Coarse-layer v3: v2 plus capacity (HIDDEN 32->128 + dropout). Step 1.2, zero download.

The one change from train_coarse_v2.py is model size: HIDDEN 32 -> 128 with a dropout
of 0.3 on the recurrent output before the head. Per-region target standardisation (v2),
spin-up, static attributes, features, EPOCHS, LR, split are all unchanged, so this run
isolates the effect of capacity alone.

WHY (motivated by diagnose_arid_root.py, not box-ticking). Step 1.1 showed the arid
weakness is not a loss-weighting problem. The root-cause diagnostic then showed it is
not an information problem either: arid GRACE is highly persistent (lag-1 autocorr 0.85)
and the per-region last-month baseline scores 0.700 there, while the v2 model scores only
0.341 -- the signal exists and the model underfits it. 35% of the arid validation variance
is a linear trend the meteorological forcing cannot see (Southwest US groundwater / drought),
so the forcing-only ceiling is ~0.6-0.65, NOT persistence's 0.70. The learnable gap 0.341 ->
~0.6 is the classic signature of a model too small to hold the slow integration arid storage
needs (measured memory optimum 30 months in arid regions). HIDDEN=128 gives it room; dropout
guards the 19,440 training region-months against overfitting.

DECISION CRITERION (Step 1.2). v2 three-seed medians: median 0.597, arid 0.341, wet 0.742.
Capacity passes if the arid third rises to >= 0.45 (a +0.11 move, above the 0.073 seed noise)
without collapsing the overall median. If it passes, capacity rescues the learnable part and
coarse-arid is worth a trend channel next. If it fails, the residual arid gap is structural
(the 35% human-water trend) and no forcing-only coarse model will fix it -- move to the
hierarchy value test (feed s_region to the fine layer) rather than grind GRACE NSE further.

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
PRED_OUT = OUT / "coarse_v3_pred.npz"

SPINUP_START = "1980-01-01"
LABEL_START = "2002-01-01"
TRAIN_END = "2010-12-31"
VAL_START = "2011-01-01"
VAL_END = "2014-12-31"
HIDDEN = 128        # was 32 in v1/v2
DROPOUT = 0.3       # new: guards the larger head
EPOCHS = 400
LR = 5e-3
SEEDS = [0, 1, 2]

SUM_VARS = ["prcp"]
MEAN_VARS = ["srad", "swe", "tmax", "tmin", "vp"]


class CoarseGRU(nn.Module):
    def __init__(self, n_feat: int, hidden: int, n_targets: int, dropout: float) -> None:
        super().__init__()
        self.gru = nn.GRU(n_feat, hidden, batch_first=True)
        self.drop = nn.Dropout(dropout)
        self.head = nn.Linear(hidden, n_targets)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        h, _ = self.gru(x)
        return self.head(self.drop(h))


def nse(obs: np.ndarray, pred: np.ndarray) -> float:
    m = np.isfinite(obs) & np.isfinite(pred)
    if m.sum() < 5:
        return float("nan")
    o, p = obs[m], pred[m]
    denom = np.sum((o - o.mean()) ** 2)
    return float(1.0 - np.sum((o - p) ** 2) / denom) if denom > 0 else float("nan")


def load_monthly() -> tuple[list[str], pd.DatetimeIndex, np.ndarray, list[str], np.ndarray, list[str]]:
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
    X = np.stack([monthly[v].values[:, sel] for v in feats], axis=-1)

    lab = xr.open_dataset(LABELS).reindex(region=regions)
    targets = [t for t in ["grace_lwe", "soil"] if t in lab]
    ltime = pd.DatetimeIndex(lab["time"].values)
    li = ltime.get_indexer(months)
    Y = np.full((len(regions), len(months), len(targets)), np.nan)
    have = li >= 0
    for k, t in enumerate(targets):
        Y[:, have, k] = lab[t].values[:, li[have]]
    return regions, months, X, feats, Y, targets


def static_attributes(X: np.ndarray, feats: list[str], train_m: np.ndarray) -> tuple[np.ndarray, list[str]]:
    pi, ti, si, ri = (feats.index(v) for v in ("prcp", "tmax", "swe", "srad"))
    stat = np.stack([
        np.log1p(np.nanmean(X[:, train_m, pi], axis=1) * 12.0),
        np.nanmean(X[:, train_m, ti], axis=1),
        np.log1p(np.nanmean(X[:, train_m, si], axis=1)),
        np.nanmean(X[:, train_m, ri], axis=1),
    ], axis=-1)
    return np.nan_to_num(stat), ["st_precip", "st_tmax", "st_swe", "st_srad"]


def per_region_target_stats(Y: np.ndarray, train_m: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
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
    torch.manual_seed(seed)
    np.random.seed(seed)
    xt = torch.tensor(Xz, dtype=torch.float32, device=dev)
    yt = torch.tensor(Yz, dtype=torch.float32, device=dev)
    mask = torch.tensor(mask_np, dtype=torch.float32, device=dev)
    ymask = yt.clone(); ymask[mask == 0] = 0.0
    tr = torch.tensor(train_m, device=dev)

    model = CoarseGRU(F, HIDDEN, K, DROPOUT).to(dev)
    opt = torch.optim.Adam(model.parameters(), lr=LR)
    model.train()
    for _ in range(EPOCHS):
        opt.zero_grad()
        se = (model(xt) - ymask) ** 2 * mask
        loss = se[:, tr].sum() / mask[:, tr].sum().clamp(min=1)
        loss.backward()
        opt.step()

    model.eval()
    with torch.no_grad():
        h_seq, _ = model.gru(xt)          # hidden state exported without dropout
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

    fstd_m = months <= TRAIN_END
    fmu = np.nanmean(X[:, fstd_m], axis=(0, 1)); fsd = np.nanstd(X[:, fstd_m], axis=(0, 1)) + 1e-6
    Xz = np.nan_to_num((X - fmu) / fsd, nan=0.0)
    tmu, tsd = per_region_target_stats(Y, train_m)
    Yz = (Y - tmu[:, None, :]) / tsd[:, None, :]
    mask_np = np.isfinite(Yz)

    dev = "cuda" if torch.cuda.is_available() else "cpu"

    ann = np.nanmean(X[:, train_m, feats.index("prcp")], axis=1) * 12.0
    q1, q2 = np.nanpercentile(ann, [33.3, 66.7])
    grp = np.where(ann <= q1, 0, np.where(ann <= q2, 1, 2))

    gi = targets.index("grace_lwe")
    print(f"regions {R}  months {T}  HIDDEN {HIDDEN}  dropout {DROPOUT}  device {dev}")
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
        print(f"seed {seed}:  median {metrics['median'][-1]:.3f}   arid {metrics['arid'][-1]:.3f}   "
              f"mid {metrics['mid'][-1]:.3f}   wet {metrics['wet'][-1]:.3f}   "
              f"NSE>0 {metrics['pos'][-1]}/{R}   pooled {metrics['pooled'][-1]:.3f}")
        if seed == SEEDS[0]:
            pred_seed0, hidden_seed0 = pred, hidden

    med = {kk: float(np.median(vv)) for kk, vv in metrics.items()}
    print(f"\n3-seed median:  median {med['median']:.3f}   arid {med['arid']:.3f}   "
          f"mid {med['mid']:.3f}   wet {med['wet']:.3f}   NSE>0 {med['pos']:.0f}/{R}   "
          f"pooled {med['pooled']:.3f}")

    v2_arid, v2_med = 0.341, 0.597
    print("\n--- Step 1.2 decision (capacity, vs v2) ---")
    print(f"  arid third: v2 {v2_arid:.3f} -> v3 {med['arid']:.3f} "
          f"(delta {med['arid'] - v2_arid:+.3f}; pass line >= 0.45; forcing-only ceiling ~0.65)")
    print(f"  overall median: v2 {v2_med:.3f} -> v3 {med['median']:.3f} "
          f"(delta {med['median'] - v2_med:+.3f}; must not collapse)")
    verdict = "PASS" if (med["arid"] >= 0.45 and med["median"] >= v2_med - 0.073) else "FAIL"
    print(f"  VERDICT: {verdict}")

    np.savez(PRED_OUT, regions=np.array(regions), months=months.astype(str).to_numpy(),
             pred=pred_seed0, obs=Y, targets=np.array(targets), val_mask=val_m, label_mask=label_m,
             hidden=hidden_seed0, feat_names=np.array(feat_names),
             seed_metrics=np.array([metrics[kk] for kk in ["median", "arid", "mid", "wet", "pos", "pooled"]]))
    print(f"\nsaved: {PRED_OUT}")


if __name__ == "__main__":
    main()
