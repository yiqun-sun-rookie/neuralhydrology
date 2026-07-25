"""Should the coarse layer's inputs change? Four literature-motivated arms, one protocol.

The memory probe (test_memory_length.py) showed GRACE needs a long antecedent window
(GRU still gaining at 192 months) and that arid regions need ~3x the memory of humid
ones (best tau 30 vs 12 months). Three published practices target exactly that:

  B  SPIN-UP. Rainfall-runoff LSTMs use a 1-3 year warm-up before scoring. v0 starts
     the sequence at 2002-01 with h=0 and throws away 22 years of forcing it owns.

  C  EXPONENTIAL PRECIP ACCUMULATORS. Humphrey et al. (2017 GRL) reconstruct GRACE
     with a first-order store, TWS(t) = TWS(t-1)*exp(-1/tau) + P(t); the filter alone
     raised precip-GRACE correlation by ~+0.3 globally. Handing the network pre-
     integrated precip at several tau removes the need to learn integration through
     hundreds of recurrent steps. tau = 3 / 12 / 36 months brackets our measured
     optimum (12 humid, 30 arid).

  D  STATIC REGION ATTRIBUTES. One shared network must use a different memory length
     per region; without a region descriptor it can only learn the average. Standard
     practice in regional/PUB machine learning.

  E  LINEAR CONTROL. Nie et al. (2025, arXiv:2510.10799) find linear regression beats
     LSTM and a Transformer at TWS prediction and that sequence length beyond 12
     months buys nothing. Their inputs include soil moisture -- a storage state, which
     hands the model the memory. Ours are meteorology only, so the two findings can
     both be true. This arm settles it here: ridge on the same accumulator + static
     features, no recurrence at all.

Same split, seeds, optimiser and target standardisation as train_coarse_v0.py.
Skill is reported overall and split by precipitation tercile, because the 39 failing
regions of v0 were the arid ones.
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd
import torch
import xarray as xr
from scipy.signal import lfilter
from torch import nn

REPO = Path(__file__).resolve().parents[3]
OUT = REPO / "results" / "25_global_flood_hierarchy" / "coarse_v0"
FORCING = OUT / "region_forcing" / "region_forcing.nc"
LABELS = OUT / "region_labels.nc"

TRAIN_END = "2010-12-31"
VAL_START, VAL_END = "2011-01-01", "2014-12-31"
SPINUP_START = "1980-01-01"
LABEL_START = "2002-01-01"
HIDDEN, EPOCHS, LR = 32, 400, 5e-3
SEEDS = [0, 1, 2]
TAUS = [3.0, 12.0, 36.0]  # months; brackets the measured optimum (12 humid, 30 arid)
RIDGE = 1.0

SUM_VARS = ["prcp"]
MEAN_VARS = ["srad", "swe", "tmax", "tmin", "vp"]


class CoarseGRU(nn.Module):
    def __init__(self, n_feat: int, hidden: int, n_targets: int) -> None:
        super().__init__()
        self.gru = nn.GRU(n_feat, hidden, batch_first=True)
        self.head = nn.Linear(hidden, n_targets)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        h, _ = self.gru(x)
        return self.head(h)


def nse(o: np.ndarray, p: np.ndarray) -> float:
    m = np.isfinite(o) & np.isfinite(p)
    if m.sum() < 5:
        return float("nan")
    o, p = o[m], p[m]
    d = np.sum((o - o.mean()) ** 2)
    return float(1.0 - np.sum((o - p) ** 2) / d) if d > 0 else float("nan")


def load() -> tuple[list[str], pd.DatetimeIndex, np.ndarray, np.ndarray, list[str], list[str]]:
    ds = xr.open_dataset(FORCING)
    regions = [str(r) for r in ds["region"].values]
    monthly = xr.Dataset()
    for v in SUM_VARS:
        monthly[v] = ds[v].resample(time="MS").sum()
    for v in MEAN_VARS:
        monthly[v] = ds[v].resample(time="MS").mean()
    feats = SUM_VARS + MEAN_VARS
    months = pd.DatetimeIndex(monthly["time"].values)
    X = np.stack([monthly[v].values for v in feats], axis=-1)  # (R, T, F)

    lab = xr.open_dataset(LABELS).reindex(region=regions)
    targets = [t for t in ["grace_lwe", "soil"] if t in lab]
    ltime = pd.DatetimeIndex(lab["time"].values)
    li = ltime.get_indexer(months)
    Y = np.full((len(regions), len(months), len(targets)), np.nan)
    have = li >= 0
    for k, t in enumerate(targets):
        Y[:, have, k] = lab[t].values[:, li[have]]
    return regions, months, X, Y, targets, feats


def add_features(X: np.ndarray, months: pd.DatetimeIndex, feats: list[str], train_m: np.ndarray,
                 acc: bool, static: bool) -> tuple[np.ndarray, list[str]]:
    """Append exponential precip accumulators and/or static region attributes.

    Both are computed from forcing only and from train months only (climatology and
    attribute means), so nothing about the validation period leaks in.
    """
    cols = [X]
    names = list(feats)
    pi = feats.index("prcp")
    p = X[:, :, pi]
    cal = months.month.to_numpy()

    if acc:
        # deseasonalise on train months: raw prcp already carries the seasonal cycle,
        # so the accumulators should carry the slow anomaly component instead.
        clim = np.zeros((p.shape[0], 12))
        for mo in range(1, 13):
            sel = train_m & (cal == mo)
            clim[:, mo - 1] = np.nanmean(p[:, sel], axis=1) if sel.any() else 0.0
        panom = np.nan_to_num(p - clim[:, cal - 1])
        for tau in TAUS:
            a = float(np.exp(-1.0 / tau))
            cols.append(lfilter([1.0], [1.0, -a], panom, axis=1)[:, :, None])
            names.append(f"pacc_tau{int(tau)}")

    if static:
        # region descriptors so one shared network can pick a per-region memory length
        stat = np.stack([
            np.log1p(np.nanmean(p[:, train_m], axis=1) * 12.0),          # annual precip
            np.nanmean(X[:, train_m, feats.index("tmax")], axis=1),      # warmth
            np.log1p(np.nanmean(X[:, train_m, feats.index("swe")], axis=1)),  # snow
            np.nanmean(X[:, train_m, feats.index("srad")], axis=1),      # energy / demand
        ], axis=-1)  # (R, S)
        cols.append(np.repeat(np.nan_to_num(stat)[:, None, :], X.shape[1], axis=1))
        names += ["st_precip", "st_tmax", "st_swe", "st_srad"]

    return np.concatenate(cols, axis=-1), names


def standardise(X: np.ndarray, Y: np.ndarray, train_m: np.ndarray):
    fmu = np.nanmean(X[:, train_m], axis=(0, 1))
    fsd = np.nanstd(X[:, train_m], axis=(0, 1)) + 1e-6
    Xz = np.nan_to_num((X - fmu) / fsd, nan=0.0)
    K = Y.shape[-1]
    tmu = np.array([np.nanmean(Y[:, train_m, k]) for k in range(K)])
    tsd = np.array([np.nanstd(Y[:, train_m, k]) + 1e-6 for k in range(K)])
    return Xz, (Y - tmu) / tsd, tmu, tsd


def run_gru(X: np.ndarray, Y: np.ndarray, months: pd.DatetimeIndex, spinup: bool,
            seed: int) -> np.ndarray:
    torch.manual_seed(seed)
    np.random.seed(seed)
    keep = months >= (SPINUP_START if spinup else LABEL_START)
    Xs, Ys, ms = X[:, keep], Y[:, keep], months[keep]
    train_m = ms <= TRAIN_END
    Xz, Yz, tmu, tsd = standardise(Xs, Ys, train_m)

    dev = "cuda" if torch.cuda.is_available() else "cpu"
    xt = torch.tensor(Xz, dtype=torch.float32, device=dev)
    yt = torch.tensor(Yz, dtype=torch.float32, device=dev)
    mask = torch.tensor(np.isfinite(Yz), dtype=torch.float32, device=dev)
    ymask = yt.clone()
    ymask[mask == 0] = 0.0
    tr = torch.tensor(train_m, device=dev)

    model = CoarseGRU(Xs.shape[-1], HIDDEN, Ys.shape[-1]).to(dev)
    opt = torch.optim.Adam(model.parameters(), lr=LR)
    for _ in range(EPOCHS):
        opt.zero_grad()
        se = (model(xt) - ymask) ** 2 * mask
        (se[:, tr].sum() / mask[:, tr].sum().clamp(min=1)).backward()
        opt.step()
    model.eval()
    with torch.no_grad():
        pred = model(xt).cpu().numpy() * tsd + tmu
    full = np.full(Y.shape, np.nan)
    full[:, keep] = pred
    return full


def run_ridge(X: np.ndarray, Y: np.ndarray, months: pd.DatetimeIndex, gi: int) -> np.ndarray:
    """Humphrey-style control: linear regression on the same instantaneous features."""
    keep = months >= LABEL_START
    Xs, Ys, ms = X[:, keep], Y[:, keep], months[keep]
    train_m = ms <= TRAIN_END
    Xz, Yz, tmu, tsd = standardise(Xs, Ys, train_m)
    R, T, F = Xz.shape
    A = np.concatenate([Xz.reshape(R * T, F), np.ones((R * T, 1))], axis=1)
    y = Yz[:, :, gi].reshape(R * T)
    trm = np.repeat(train_m[None, :], R, axis=0).reshape(R * T) & np.isfinite(y)
    At, yt_ = A[trm], y[trm]
    w = np.linalg.solve(At.T @ At + RIDGE * np.eye(A.shape[1]), At.T @ yt_)
    pz = (A @ w).reshape(R, T)
    full = np.full(Y.shape, np.nan)
    full[:, keep, gi] = pz * tsd[gi] + tmu[gi]
    return full


def per_region_nse(pred: np.ndarray, Y: np.ndarray, months: pd.DatetimeIndex, gi: int) -> np.ndarray:
    val = (months >= VAL_START) & (months <= VAL_END)
    o, p = Y[:, val, gi], pred[:, val, gi]
    return np.array([nse(o[i], p[i]) for i in range(o.shape[0])])


def pooled_nse(pred: np.ndarray, Y: np.ndarray, months: pd.DatetimeIndex, gi: int) -> float:
    val = (months >= VAL_START) & (months <= VAL_END)
    return nse(Y[:, val, gi].ravel(), pred[:, val, gi].ravel())


def main() -> None:
    regions, months, X0, Y, targets, feats = load()
    gi = targets.index("grace_lwe")
    train_m_full = (months >= LABEL_START) & (months <= TRAIN_END)

    X_acc, n_acc = add_features(X0, months, feats, train_m_full, acc=True, static=False)
    X_st, _ = add_features(X0, months, feats, train_m_full, acc=False, static=True)
    X_all, n_all = add_features(X0, months, feats, train_m_full, acc=True, static=True)

    # aridity terciles from train-period precip (an input, so no label leakage).
    # prcp is a monthly total, so annual = monthly mean x 12.
    ann = np.nanmean(X0[:, train_m_full, feats.index("prcp")], axis=1) * 12.0
    q1, q2 = np.nanpercentile(ann, [33.3, 66.7])
    grp = np.where(ann <= q1, 0, np.where(ann <= q2, 1, 2))
    gname = ["dry", "mid", "wet"]

    # S is the missing control: the C->D increment is path-dependent, so statics are
    # also tested WITHOUT accumulators to see which of the two actually carries the gain.
    arms = [
        ("A v0 (no spin-up, 6 feat)", lambda s: run_gru(X0, Y, months, False, s)),
        # mechanism check: if accumulators substitute for the recurrent integration that
        # spin-up enables, they should pay off here (no spin-up) and not in C (spin-up).
        ("A' acc, no spin-up", lambda s: run_gru(X_acc, Y, months, False, s)),
        ("B + spin-up 1980", lambda s: run_gru(X0, Y, months, True, s)),
        ("C + precip accumulators", lambda s: run_gru(X_acc, Y, months, True, s)),
        ("S + static only (no acc)", lambda s: run_gru(X_st, Y, months, True, s)),
        ("D + acc + static", lambda s: run_gru(X_all, Y, months, True, s)),
        ("E ridge, no recurrence", lambda s: run_ridge(X_all, Y, months, gi)),
    ]

    print(f"regions {len(regions)}  months {len(months)} "
          f"({months.min().date()}..{months.max().date()})")
    print(f"features: base {len(feats)} | +acc {len(n_acc)} | +static {len(n_all)}  -> {n_all[6:]}")
    print(f"aridity terciles (mm/yr): dry <={q1:.0f}  mid <={q2:.0f}  wet >  "
          f"(n={[int((grp == g).sum()) for g in range(3)]})")
    print()
    hdr = f"{'arm':28s} {'pooled':>7s} {'median':>7s} {'seed range':>14s} {'NSE>0':>6s}   " \
          f"{'dry':>7s} {'mid':>7s} {'wet':>7s}"
    print(hdr)
    print("-" * len(hdr))

    table = {}
    for name, fn in arms:
        pooled, med, npos, bygrp = [], [], [], {g: [] for g in range(3)}
        for s in SEEDS:
            pred = fn(s)
            pooled.append(pooled_nse(pred, Y, months, gi))
            per = per_region_nse(pred, Y, months, gi)
            med.append(np.nanmedian(per))
            npos.append(int(np.nansum(per > 0)))
            for g in range(3):
                bygrp[g].append(np.nanmedian(per[grp == g]))
        row = dict(pooled=float(np.median(pooled)), med=float(np.median(med)),
                   lo=float(np.min(med)), hi=float(np.max(med)), npos=int(np.median(npos)),
                   grp=[float(np.median(bygrp[g])) for g in range(3)])
        table[name] = row
        print(f"{name:28s} {row['pooled']:7.3f} {row['med']:7.3f} "
              f"{row['lo']:6.3f}..{row['hi']:<7.3f} {row['npos']:6d}   "
              f"{row['grp'][0]:7.3f} {row['grp'][1]:7.3f} {row['grp'][2]:7.3f}")

    print()
    print("=== effect vs the v0 baseline (median per-region NSE) ===")
    keys = [k for k, _ in arms]
    base = table[keys[0]]
    spread = max(t["hi"] - t["lo"] for t in table.values())
    for k in keys[1:]:
        t = table[k]
        print(f"  {k:26s} {t['med'] - base['med']:+.3f}   "
              f"(dry {t['grp'][0] - base['grp'][0]:+.3f}  "
              f"wet {t['grp'][2] - base['grp'][2]:+.3f})")
    print(f"  largest across-seed spread of any arm: {spread:.3f} "
          "(differences smaller than this are not resolved by 3 seeds)")


if __name__ == "__main__":
    main()
