"""How long an input window does GRACE storage actually require?

GRACE total water storage at month t is physically the running integral of
(P - ET - Q) over the preceding period. To predict S(t) from forcing you must feed
forcing back over the system's memory timescale -- if the input window is shorter
than that memory, the information is simply absent from the inputs and no model can
recover it. That is an identifiability constraint, not a hyperparameter.

Two independent estimates, so neither depends on the network's fitting ability:

  PART 1 (model-free). Correlate GRACE against precipitation anomaly accumulated over
     a trailing window. Two accumulators: a boxcar of L months (directly answers "how
     many months must I feed") and an exponential decay of timescale tau (the physical
     memory constant). The L / tau that maximises correlation is the required window.
     Run separately on raw GRACE (seasonal cycle included) and on deseasonalised GRACE
     (slow component only) -- these have very different memory, and conflating them is
     what makes a short window look adequate.

  PART 2 (model-based). Retrain the coarse GRU on a strictly truncated sliding window
     of L months (hidden state reset at each window start) and score validation skill
     against L. Where the curve flattens is the window the model actually needs.

Also reports the required window split by aridity, since deep-groundwater arid regions
should integrate far longer than humid ones.
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd
import torch
import xarray as xr
from numpy.lib.stride_tricks import sliding_window_view
from scipy.signal import lfilter
from torch import nn

REPO = Path(__file__).resolve().parents[3]
OUT = REPO / "results" / "25_global_flood_hierarchy" / "coarse_v0"
FORCING = OUT / "region_forcing" / "region_forcing.nc"
LABELS = OUT / "region_labels.nc"

VAL_START, VAL_END, TRAIN_END = "2011-01-01", "2014-12-31", "2010-12-31"
BOXCAR_L = [1, 2, 3, 6, 9, 12, 18, 24, 36, 48, 60, 96, 120, 180, 240]
TAUS = [0.5, 1, 2, 3, 6, 12, 24, 36, 60, 120]
GRU_L = [3, 6, 12, 24, 48, 96, 192]
SEEDS = [0, 1, 2]
HIDDEN, LR, EPOCHS, BATCH = 32, 5e-3, 60, 1024

SUM_VARS = ["prcp"]
MEAN_VARS = ["srad", "swe", "tmax", "tmin", "vp"]


def load() -> tuple[list[str], pd.DatetimeIndex, np.ndarray, np.ndarray, list[str]]:
    ds = xr.open_dataset(FORCING)
    regions = [str(r) for r in ds["region"].values]
    monthly = xr.Dataset()
    for v in SUM_VARS:
        monthly[v] = ds[v].resample(time="MS").sum()
    for v in MEAN_VARS:
        monthly[v] = ds[v].resample(time="MS").mean()
    feats = SUM_VARS + MEAN_VARS
    months = pd.DatetimeIndex(monthly["time"].values)
    X = np.stack([monthly[v].values for v in feats], axis=-1)

    lab = xr.open_dataset(LABELS).reindex(region=regions)
    ltime = pd.DatetimeIndex(lab["time"].values)
    li = ltime.get_indexer(months)
    G = np.full((len(regions), len(months)), np.nan)
    have = li >= 0
    G[:, have] = lab["grace_lwe"].values[:, li[have]]
    return regions, months, X, G, feats


def deseasonalise(y: np.ndarray, months: pd.DatetimeIndex) -> np.ndarray:
    """Subtract the per-region month-of-year mean; leaves the slow component."""
    out = y.copy()
    cal = months.month
    for mo in range(1, 13):
        sel = cal == mo
        out[:, sel] -= np.nanmean(y[:, sel], axis=1, keepdims=True)
    return out


def rowwise_corr(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """Pearson r per row, ignoring months where either is NaN."""
    R = a.shape[0]
    r = np.full(R, np.nan)
    for i in range(R):
        m = np.isfinite(a[i]) & np.isfinite(b[i])
        if m.sum() < 24:
            continue
        x, y = a[i, m], b[i, m]
        sx, sy = x.std(), y.std()
        if sx < 1e-12 or sy < 1e-12:
            continue
        r[i] = float(np.mean((x - x.mean()) * (y - y.mean())) / (sx * sy))
    return r


def part1(regions, months, X, G, feats, precip_ann) -> None:
    P = X[:, :, feats.index("prcp")]
    Panom = P - np.stack([np.nanmean(P[:, months.month == m], axis=1) for m in months.month], axis=1)

    G_raw = G
    G_slow = deseasonalise(G, months)

    T = Panom.shape[1]
    # c0[:, t] = sum of Panom[:, :t]; trailing L-sum ending at t is c0[t+1] - c0[t+1-L]
    c0 = np.concatenate([np.zeros((Panom.shape[0], 1)), np.cumsum(np.nan_to_num(Panom), axis=1)], axis=1)
    print("PART 1  model-free: precipitation accumulated over a trailing window vs GRACE")
    print("        (median Pearson r across 180 regions; correlation only, no model)")
    print(f"{'window L (months)':>18s} {'raw GRACE':>11s} {'slow GRACE':>11s}")
    box = {}
    for L in BOXCAR_L:
        acc = np.full_like(Panom, np.nan)
        acc[:, L - 1:] = c0[:, L:] - c0[:, :T - L + 1]
        box[L] = (rowwise_corr(acc, G_raw), rowwise_corr(acc, G_slow))
        print(f"{L:18d} {np.nanmedian(box[L][0]):11.3f} {np.nanmedian(box[L][1]):11.3f}")

    Lstar_raw = np.array([BOXCAR_L[int(np.nanargmax([box[L][0][i] for L in BOXCAR_L]))]
                          if np.isfinite([box[L][0][i] for L in BOXCAR_L]).any() else np.nan
                          for i in range(len(regions))], dtype=float)
    Lstar_slow = np.array([BOXCAR_L[int(np.nanargmax([box[L][1][i] for L in BOXCAR_L]))]
                           if np.isfinite([box[L][1][i] for L in BOXCAR_L]).any() else np.nan
                           for i in range(len(regions))], dtype=float)
    print(f"\n  best window per region, median : raw {np.nanmedian(Lstar_raw):.0f} months   "
          f"slow {np.nanmedian(Lstar_slow):.0f} months")
    print(f"  best window, 25-75 pct (slow)  : "
          f"{np.nanpercentile(Lstar_slow, 25):.0f} - {np.nanpercentile(Lstar_slow, 75):.0f} months")

    print("\n  exponential memory timescale tau (physical decay constant):")
    print(f"{'tau (months)':>18s} {'raw GRACE':>11s} {'slow GRACE':>11s}")
    tau_r = {}
    for tau in TAUS:
        a = float(np.exp(-1.0 / tau))
        acc = lfilter([1.0], [1.0, -a], np.nan_to_num(Panom), axis=1)
        tau_r[tau] = (rowwise_corr(acc, G_raw), rowwise_corr(acc, G_slow))
        print(f"{tau:18.1f} {np.nanmedian(tau_r[tau][0]):11.3f} {np.nanmedian(tau_r[tau][1]):11.3f}")
    tstar = np.array([TAUS[int(np.nanargmax([tau_r[t][1][i] for t in TAUS]))]
                      if np.isfinite([tau_r[t][1][i] for t in TAUS]).any() else np.nan
                      for i in range(len(regions))], dtype=float)
    print(f"\n  best tau per region (slow), median: {np.nanmedian(tstar):.0f} months "
          f"-> a boxcar of ~3 tau = {3*np.nanmedian(tstar):.0f} months captures 95%")

    # does aridity lengthen the required window?
    q = np.nanpercentile(precip_ann, [33, 67])
    grp = np.digitize(precip_ann, q)
    names = ["dry (driest third)", "middle", "wet (wettest third)"]
    print("\n  required window by aridity (slow component):")
    for g, nm in enumerate(names):
        sel = grp == g
        print(f"    {nm:20s} n={int(sel.sum()):3d}  precip {np.nanmedian(precip_ann[sel]):5.0f} mm/yr  "
              f"median best L {np.nanmedian(Lstar_slow[sel]):5.0f} mo  "
              f"median best tau {np.nanmedian(tstar[sel]):4.0f} mo")


class WinGRU(nn.Module):
    def __init__(self, n_feat: int, hidden: int) -> None:
        super().__init__()
        self.gru = nn.GRU(n_feat, hidden, batch_first=True)
        self.head = nn.Linear(hidden, 1)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        h, _ = self.gru(x)
        return self.head(h[:, -1])  # predict the target at the window's last month


def part2(regions, months, X, G) -> None:
    train_m = months <= TRAIN_END
    val_m = (months >= VAL_START) & (months <= VAL_END)
    fmu = np.nanmean(X[:, train_m], axis=(0, 1))
    fsd = np.nanstd(X[:, train_m], axis=(0, 1)) + 1e-6
    Xz = np.nan_to_num((X - fmu) / fsd, nan=0.0)
    gmu = np.nanmean(G[:, train_m])
    gsd = np.nanstd(G[:, train_m]) + 1e-6
    Gz = (G - gmu) / gsd
    dev = "cuda" if torch.cuda.is_available() else "cpu"
    R, T, F = Xz.shape

    print("\n\nPART 2  model-based: GRU on a strictly truncated sliding window")
    print("        (state reset at each window start; val 2011-2014, median of 3 seeds)")
    print(f"{'window L (months)':>18s} {'pooled NSE':>11s} {'median NSE':>11s} {'NSE>0':>7s}")
    prev = None
    for L in GRU_L:
        ridx, tidx = np.where(np.isfinite(G) & (np.arange(T)[None, :] >= L - 1))
        # zero-copy view: W[r, j] is the window Xz[r, j:j+L] -> window ending at t is j = t-L+1
        W = sliding_window_view(Xz, L, axis=1)  # (R, T-L+1, F, L)

        def windows(keys: np.ndarray) -> np.ndarray:
            return np.ascontiguousarray(W[ridx[keys], tidx[keys] - L + 1].transpose(0, 2, 1))
        is_tr = train_m[tidx]
        is_va = val_m[tidx]
        seeds_out = []
        for seed in SEEDS:
            torch.manual_seed(seed)
            np.random.seed(seed)
            model = WinGRU(F, HIDDEN).to(dev)
            opt = torch.optim.Adam(model.parameters(), lr=LR)
            tr_pos = np.where(is_tr)[0]
            for _ in range(EPOCHS):
                perm = np.random.permutation(tr_pos)
                for s in range(0, len(perm), BATCH):
                    sel = perm[s:s + BATCH]
                    xb = torch.tensor(windows(sel), dtype=torch.float32, device=dev)
                    yb = Gz[ridx[sel], tidx[sel]]
                    yb = torch.tensor(yb, dtype=torch.float32, device=dev)
                    opt.zero_grad()
                    loss = ((model(xb).squeeze(-1) - yb) ** 2).mean()
                    loss.backward()
                    opt.step()
            model.eval()
            va_pos = np.where(is_va)[0]
            preds = []
            with torch.no_grad():
                for s in range(0, len(va_pos), 2048):
                    sel = va_pos[s:s + 2048]
                    xb = torch.tensor(windows(sel), dtype=torch.float32, device=dev)
                    preds.append(model(xb).squeeze(-1).cpu().numpy())
            p = np.concatenate(preds) * gsd + gmu
            o = G[ridx[va_pos], tidx[va_pos]]
            pooled = 1 - np.sum((o - p) ** 2) / np.sum((o - o.mean()) ** 2)
            per = []
            for i in range(R):
                m = ridx[va_pos] == i
                if m.sum() < 5:
                    continue
                oo, pp = o[m], p[m]
                d = np.sum((oo - oo.mean()) ** 2)
                per.append(1 - np.sum((oo - pp) ** 2) / d if d > 0 else np.nan)
            per = np.array(per)
            seeds_out.append((pooled, np.nanmedian(per), int(np.nansum(per > 0))))
        pooled = float(np.median([s[0] for s in seeds_out]))
        medn = float(np.median([s[1] for s in seeds_out]))
        npos = int(np.median([s[2] for s in seeds_out]))
        gain = "" if prev is None else f"   (+{pooled - prev:.3f} vs previous L)"
        print(f"{L:18d} {pooled:11.3f} {medn:11.3f} {npos:7d}{gain}")
        prev = pooled


def main() -> None:
    regions, months, X, G, feats = load()
    precip_ann = np.nanmean(X[:, :, feats.index("prcp")], axis=1) * 12
    part1(regions, months, X, G, feats, precip_ann)
    part2(regions, months, X, G)


if __name__ == "__main__":
    main()
