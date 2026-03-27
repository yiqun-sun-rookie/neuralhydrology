"""TANGO per-basin validation: each basin trained independently.

For each basin:
  E1: Pure HBV (L-BFGS calibrated)
  E2: Pure LSTM (normalized, 100 epochs)
  E3: TANGO stride=10 (150 epochs, per-basin HBV params + state stats)

This isolates the architecture's capability from multi-basin confounds.
"""
import sys
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from scl_hydro.hbv_torch import DifferentiableHBV, PARAM_NAMES
from scl_hydro.coupled_model import CoupledHydroModel
from scl_hydro.data_utils import load_camels_basins

DATA_DIR = Path(__file__).parent.parent.parent.parent / "data" / "camels_us"
BASINS = ["01013500", "01022500", "02051500", "03450000",
          "07056000", "07291000", "09035900", "12010000"]
FEATURES = ["prcp(mm/day)", "srad(W/m2)", "tmax(C)", "tmin(C)", "vp(Pa)"]
TARGET = "QObs(mm/d)"
SEG = 180
STRIDE = 10


def nse(obs, sim):
    m = np.isfinite(obs) & np.isfinite(sim)
    o, s = obs[m], sim[m]
    if len(o) < 10:
        return float("nan")
    return float(1 - np.sum((s - o) ** 2) / np.sum((o - o.mean()) ** 2))


def prep_basin(basin):
    fcols = ["prcp(mm/day)", "pet", "tmean"]
    train = load_camels_basins(DATA_DIR, [basin], FEATURES, TARGET,
                               "1999-10-01", "2008-09-30")[basin]
    test = load_camels_basins(DATA_DIR, [basin], FEATURES, TARGET,
                              "1989-10-01", "1999-09-30")[basin]
    for df in [train, test]:
        srad = df["srad(W/m2)"].values
        df["pet"] = np.maximum(0, 0.65 * srad * 0.0864 / 2.45).astype(np.float32)
        df["tmean"] = ((df["tmax(C)"] + df["tmin(C)"]) / 2).astype(np.float32)

    f_tr = train[fcols].values.astype(np.float32)
    t_tr = train[[TARGET]].values.astype(np.float32)
    f_te = test[fcols].values.astype(np.float32)

    segs_f, segs_t = [], []
    for start in range(0, len(f_tr) - SEG, SEG // 2):
        sf, st = f_tr[start:start + SEG], t_tr[start:start + SEG]
        if not np.any(np.isnan(st)):
            segs_f.append(sf)
            segs_t.append(st)

    f_mean = f_tr.mean(0)
    f_std = f_tr.std(0)
    f_std[f_std < 1e-6] = 1
    t_mean = float(np.nanmean(t_tr))
    t_std = float(np.nanstd(t_tr))

    return train, test, fcols, np.array(segs_f), np.array(segs_t), f_mean, f_std, t_mean, t_std, f_te


def calibrate_hbv(train, fcols):
    hbv = DifferentiableHBV()
    forcing = torch.tensor(
        np.stack([train[c].values for c in fcols], axis=-1)[np.newaxis], dtype=torch.float32)
    q_obs = torch.tensor(train[TARGET].values[np.newaxis, :, np.newaxis], dtype=torch.float32)
    mask = ~torch.isnan(q_obs)

    raw = torch.zeros(1, 10, requires_grad=True)
    opt = torch.optim.LBFGS([raw], lr=0.3, max_iter=20, line_search_fn="strong_wolfe")
    for _ in range(15):
        def closure():
            opt.zero_grad()
            p = hbv.constrain_params(raw)
            _, q, _ = hbv(forcing, p)
            loss = nn.functional.mse_loss(q[mask], q_obs[mask])
            loss.backward()
            return loss
        opt.step(closure)

    cal = {n: hbv.constrain_params(raw)[n][0, 0].item() for n in PARAM_NAMES}

    with torch.no_grad():
        p = hbv.constrain_params(raw)
        _, _, states = hbv(forcing, p)
        _, q_raw, _ = hbv(forcing, p)

    s = states[0].numpy()
    q = q_raw[0, :, 0].numpy()
    s_mean = torch.tensor(s.mean(0).astype(np.float32))
    s_std = torch.tensor(s.std(0).astype(np.float32))
    s_std[s_std < 1] = 1.0
    q_m, q_s = float(q.mean()), max(float(q.std()), 0.5)

    return cal, s_mean, s_std, q_m, q_s


def eval_hbv(cal, test, fcols):
    hbv = DifferentiableHBV()
    f_te = torch.tensor(
        np.stack([test[c].values for c in fcols], axis=-1)[np.newaxis], dtype=torch.float32)
    p = hbv.dict_from_values(cal)
    with torch.no_grad():
        _, q_te, _ = hbv(f_te, p)
    return nse(test[TARGET].values, q_te[0, :, 0].numpy())


def train_lstm(segs_f, segs_t, f_mean, f_std, t_mean, t_std):
    torch.manual_seed(42)
    sf_norm = torch.tensor((segs_f - f_mean) / f_std)
    st_norm = torch.tensor((segs_t - t_mean) / t_std)
    lstm = nn.LSTM(3, 64, batch_first=True)
    head = nn.Linear(64, 1)
    allp = list(lstm.parameters()) + list(head.parameters())
    opt = torch.optim.Adam(allp, lr=0.001)
    for ep in range(100):
        lstm.train()
        head.train()
        idx = torch.randperm(len(sf_norm))
        for i in range(0, len(idx), 8):
            bi = idx[i:i + 8]
            if len(bi) < 2:
                continue
            o = head(lstm(sf_norm[bi])[0])
            m = ~torch.isnan(st_norm[bi])
            loss = nn.functional.mse_loss(o[m], st_norm[bi][m])
            opt.zero_grad()
            loss.backward()
            nn.utils.clip_grad_norm_(allp, 1.0)
            opt.step()
    return lstm, head


def eval_lstm(lstm, head, test, fcols, f_mean, f_std, t_mean, t_std):
    lstm.eval()
    head.eval()
    f_te = test[fcols].values.astype(np.float32)
    preds = []
    with torch.no_grad():
        for start in range(0, len(f_te) - SEG, SEG):
            sf = (f_te[start:start + SEG] - f_mean) / f_std
            q = head(lstm(torch.tensor(sf[np.newaxis]))[0])[0, :, 0].numpy()
            preds.append(q * t_std + t_mean)
    return nse(test[TARGET].values[:len(np.concatenate(preds))], np.concatenate(preds))


def train_tango(segs_f, segs_t, cal, f_mean, f_std, s_mean, s_std, q_m, q_s):
    torch.manual_seed(42)
    sf_t = torch.tensor(segs_f)
    st_t = torch.tensor(segs_t)
    model = CoupledHydroModel(
        n_forcing=3, hidden_size=64, hbv_params=cal,
        forcing_mean=torch.tensor(f_mean), forcing_std=torch.tensor(f_std),
        state_mean=s_mean, state_std=s_std, q_mean=q_m, q_std=q_s,
        stride=STRIDE,
    )
    opt = torch.optim.Adam(model.parameters(), lr=0.003)
    for ep in range(150):
        model.train()
        idx = torch.randperm(len(sf_t))
        for i in range(0, len(idx), 8):
            bi = idx[i:i + 8]
            if len(bi) < 2:
                continue
            out = model(sf_t[bi])
            m = ~torch.isnan(st_t[bi])
            if m.sum() == 0:
                continue
            loss = nn.functional.mse_loss(out["y_hat"][m], st_t[bi][m])
            if torch.isnan(loss):
                continue
            opt.zero_grad()
            loss.backward()
            nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            opt.step()
    return model


def eval_tango(model, test, fcols):
    model.eval()
    f_te = test[fcols].values.astype(np.float32)
    preds = []
    with torch.no_grad():
        for start in range(0, len(f_te) - SEG, SEG):
            out = model(torch.tensor(f_te[start:start + SEG][np.newaxis]))
            preds.append(out["y_hat"][0, :, 0].numpy())
    return nse(test[TARGET].values[:len(np.concatenate(preds))], np.concatenate(preds))


def main():
    print(f"=== TANGO Per-Basin Validation (stride={STRIDE}) ===\n")

    results = {}
    for basin in BASINS:
        print(f"--- {basin} ---")
        train, test, fcols, segs_f, segs_t, f_mean, f_std, t_mean, t_std, f_te = prep_basin(basin)
        print(f"  Segments: {len(segs_f)}")

        # E1: HBV
        cal, s_mean, s_std, q_m, q_s = calibrate_hbv(train, fcols)
        nse_hbv = eval_hbv(cal, test, fcols)

        # E2: LSTM
        lstm, head = train_lstm(segs_f, segs_t, f_mean, f_std, t_mean, t_std)
        nse_lstm = eval_lstm(lstm, head, test, fcols, f_mean, f_std, t_mean, t_std)

        # E3: TANGO
        model = train_tango(segs_f, segs_t, cal, f_mean, f_std, s_mean, s_std, q_m, q_s)
        nse_tango = eval_tango(model, test, fcols)

        results[basin] = {"hbv": nse_hbv, "lstm": nse_lstm, "tango": nse_tango}
        print(f"  HBV={nse_hbv:.4f}  LSTM={nse_lstm:.4f}  TANGO={nse_tango:.4f}  "
              f"T-H={nse_tango - nse_hbv:+.4f}  T-L={nse_tango - nse_lstm:+.4f}")

    # Summary
    print(f"\n{'=' * 62}")
    print(f"{'Basin':>12s} | {'HBV':>6s} | {'LSTM':>6s} | {'TANGO':>6s} | {'T-H':>6s} | {'T-L':>6s}")
    print(f"{'-' * 12}-+-{'-' * 6}-+-{'-' * 6}-+-{'-' * 6}-+-{'-' * 6}-+-{'-' * 6}")
    for b in BASINS:
        r = results[b]
        print(f"{b:>12s} | {r['hbv']:6.3f} | {r['lstm']:6.3f} | {r['tango']:6.3f} | "
              f"{r['tango'] - r['hbv']:+6.3f} | {r['tango'] - r['lstm']:+6.3f}")

    v_h = [results[b]["hbv"] for b in BASINS]
    v_l = [results[b]["lstm"] for b in BASINS]
    v_t = [results[b]["tango"] for b in BASINS]
    print(f"{'-' * 12}-+-{'-' * 6}-+-{'-' * 6}-+-{'-' * 6}-+-{'-' * 6}-+-{'-' * 6}")
    print(f"{'Mean':>12s} | {np.mean(v_h):6.3f} | {np.mean(v_l):6.3f} | {np.mean(v_t):6.3f} | "
          f"{np.mean(v_t) - np.mean(v_h):+6.3f} | {np.mean(v_t) - np.mean(v_l):+6.3f}")
    print(f"{'Median':>12s} | {np.median(v_h):6.3f} | {np.median(v_l):6.3f} | {np.median(v_t):6.3f} | "
          f"{np.median(v_t) - np.median(v_h):+6.3f} | {np.median(v_t) - np.median(v_l):+6.3f}")

    wins_h = sum(1 for b in BASINS if results[b]["tango"] > results[b]["hbv"])
    wins_l = sum(1 for b in BASINS if results[b]["tango"] > results[b]["lstm"])
    print(f"\nTANGO wins vs HBV: {wins_h}/8")
    print(f"TANGO wins vs LSTM: {wins_l}/8")


if __name__ == "__main__":
    main()
