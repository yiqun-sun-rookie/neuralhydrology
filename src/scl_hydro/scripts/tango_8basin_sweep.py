"""TANGO 8-basin stride sweep: HBV vs LSTM vs TANGO(stride=2,5,10)."""
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


def nse(obs, sim):
    m = np.isfinite(obs) & np.isfinite(sim)
    o, s = obs[m], sim[m]
    if len(o) < 10:
        return float("nan")
    return float(1 - np.sum((s - o) ** 2) / np.sum((o - o.mean()) ** 2))


def main():
    fcols = ["prcp(mm/day)", "pet", "tmean"]

    # Load
    print("Loading data...")
    train_all, test_all = {}, {}
    for b in BASINS:
        train_all[b] = load_camels_basins(DATA_DIR, [b], FEATURES, TARGET,
                                          "1999-10-01", "2008-09-30")[b]
        test_all[b] = load_camels_basins(DATA_DIR, [b], FEATURES, TARGET,
                                         "1989-10-01", "1999-09-30")[b]
        for df in [train_all[b], test_all[b]]:
            srad = df["srad(W/m2)"].values
            df["pet"] = np.maximum(0, 0.65 * srad * 0.0864 / 2.45).astype(np.float32)
            df["tmean"] = ((df["tmax(C)"] + df["tmin(C)"]) / 2).astype(np.float32)

    hbv = DifferentiableHBV()

    # Calibrate HBV
    print("\nCalibrating HBV...")
    t0 = time.time()
    cal_params, nse_hbv = {}, {}
    for b in BASINS:
        forcing = torch.tensor(
            np.stack([train_all[b][c].values for c in fcols], axis=-1)[np.newaxis],
            dtype=torch.float32)
        q_obs = torch.tensor(
            train_all[b][TARGET].values[np.newaxis, :, np.newaxis], dtype=torch.float32)
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
        cal_params[b] = {n: hbv.constrain_params(raw)[n][0, 0].item() for n in PARAM_NAMES}
        with torch.no_grad():
            p = hbv.constrain_params(raw)
            f_te = torch.tensor(
                np.stack([test_all[b][c].values for c in fcols], axis=-1)[np.newaxis],
                dtype=torch.float32)
            _, q_te, _ = hbv(f_te, p)
            nse_hbv[b] = nse(test_all[b][TARGET].values, q_te[0, :, 0].numpy())
        print(f"  {b}: {nse_hbv[b]:.4f}")
    print(f"  Time: {time.time() - t0:.0f}s")

    # State stats
    all_states = []
    for b in BASINS:
        forcing = torch.tensor(
            np.stack([train_all[b][c].values for c in fcols], axis=-1)[np.newaxis],
            dtype=torch.float32)
        p = hbv.dict_from_values(cal_params[b])
        with torch.no_grad():
            _, _, states = hbv(forcing, p)
        all_states.append(states[0].numpy())
    all_s = np.concatenate(all_states, axis=0)
    s_mean = torch.tensor(all_s.mean(0).astype(np.float32))
    s_std = torch.tensor(all_s.std(0).astype(np.float32))
    s_std[s_std < 1] = 1.0

    # Build pooled segments
    all_f, all_t = [], []
    for b in BASINS:
        f = train_all[b][fcols].values.astype(np.float32)
        t = train_all[b][[TARGET]].values.astype(np.float32)
        for start in range(0, len(f) - SEG, SEG // 2):
            sf, st = f[start:start + SEG], t[start:start + SEG]
            if not np.any(np.isnan(st)):
                all_f.append(sf)
                all_t.append(st)
    all_f = np.array(all_f)
    all_t = np.array(all_t)
    f_mean = all_f.reshape(-1, 3).mean(0).astype(np.float32)
    f_std_v = all_f.reshape(-1, 3).std(0).astype(np.float32)
    f_std_v[f_std_v < 1e-6] = 1
    t_mean_v = float(np.nanmean(all_t))
    t_std_v = float(np.nanstd(all_t))
    print(f"\nPooled segments: {len(all_f)}")

    # Pure LSTM
    print("\n=== Pure LSTM ===")
    torch.manual_seed(42)
    sf_norm = torch.tensor((all_f - f_mean) / f_std_v)
    st_norm = torch.tensor((all_t - t_mean_v) / t_std_v)
    lstm = nn.LSTM(3, 64, batch_first=True)
    head = nn.Linear(64, 1)
    allp = list(lstm.parameters()) + list(head.parameters())
    opt2 = torch.optim.Adam(allp, lr=0.001)
    for ep in range(100):
        lstm.train()
        head.train()
        idx = torch.randperm(len(sf_norm))
        for i in range(0, len(idx), 16):
            bi = idx[i:i + 16]
            if len(bi) < 2:
                continue
            o = head(lstm(sf_norm[bi])[0])
            m = ~torch.isnan(st_norm[bi])
            loss = nn.functional.mse_loss(o[m], st_norm[bi][m])
            opt2.zero_grad()
            loss.backward()
            nn.utils.clip_grad_norm_(allp, 1.0)
            opt2.step()
    lstm.eval()
    head.eval()
    nse_lstm = {}
    for b in BASINS:
        f_te = test_all[b][fcols].values.astype(np.float32)
        preds = []
        with torch.no_grad():
            for start in range(0, len(f_te) - SEG, SEG):
                sf = (f_te[start:start + SEG] - f_mean) / f_std_v
                q = head(lstm(torch.tensor(sf[np.newaxis]))[0])[0, :, 0].numpy()
                preds.append(q * t_std_v + t_mean_v)
        nse_lstm[b] = nse(test_all[b][TARGET].values[:len(np.concatenate(preds))],
                          np.concatenate(preds))
    print(f"  Mean: {np.mean(list(nse_lstm.values())):.4f}")

    # TANGO strides
    avg_params = {name: float(np.mean([cal_params[b][name] for b in BASINS]))
                  for name in PARAM_NAMES}
    sf_t = torch.tensor(all_f)
    st_t = torch.tensor(all_t)

    nse_tango = {}
    for stride in [2, 5, 10]:
        print(f"\n=== TANGO stride={stride} ===")
        torch.manual_seed(42)
        model = CoupledHydroModel(
            n_forcing=3, hidden_size=64, hbv_params=avg_params,
            forcing_mean=torch.tensor(f_mean), forcing_std=torch.tensor(f_std_v),
            state_mean=s_mean, state_std=s_std, q_mean=1.5, q_std=2.5,
            stride=stride,
        )
        opt3 = torch.optim.Adam(model.parameters(), lr=0.003)
        for ep in range(150):
            model.train()
            idx = torch.randperm(len(sf_t))
            for i in range(0, len(idx), 16):
                bi = idx[i:i + 16]
                if len(bi) < 2:
                    continue
                out = model(sf_t[bi])
                m = ~torch.isnan(st_t[bi])
                if m.sum() == 0:
                    continue
                loss = nn.functional.mse_loss(out["y_hat"][m], st_t[bi][m])
                if torch.isnan(loss):
                    continue
                opt3.zero_grad()
                loss.backward()
                nn.utils.clip_grad_norm_(model.parameters(), 1.0)
                opt3.step()
        model.eval()
        nse_tango[stride] = {}
        for b in BASINS:
            f_te = test_all[b][fcols].values.astype(np.float32)
            preds = []
            with torch.no_grad():
                for start in range(0, len(f_te) - SEG, SEG):
                    out = model(torch.tensor(f_te[start:start + SEG][np.newaxis]))
                    preds.append(out["y_hat"][0, :, 0].numpy())
            nse_tango[stride][b] = nse(
                test_all[b][TARGET].values[:len(np.concatenate(preds))],
                np.concatenate(preds))
        print(f"  Mean: {np.mean(list(nse_tango[stride].values())):.4f}")

    # Results table
    print(f"\n{'=' * 72}")
    h = f"{'Basin':>12s} | {'HBV':>6s} | {'LSTM':>6s}"
    for s in [2, 5, 10]:
        h += f" | {'T-' + str(s):>6s}"
    print(h)
    sep = f"{'-' * 12}-+-{'-' * 6}-+-{'-' * 6}" + "".join([f"-+-{'-' * 6}" for _ in [2, 5, 10]])
    print(sep)
    for b in BASINS:
        row = f"{b:>12s} | {nse_hbv[b]:6.3f} | {nse_lstm[b]:6.3f}"
        for s in [2, 5, 10]:
            row += f" | {nse_tango[s][b]:6.3f}"
        print(row)
    print(sep)
    row = f"{'Mean':>12s} | {np.mean(list(nse_hbv.values())):6.3f} | {np.mean(list(nse_lstm.values())):6.3f}"
    for s in [2, 5, 10]:
        row += f" | {np.mean(list(nse_tango[s].values())):6.3f}"
    print(row)
    row = f"{'Median':>12s} | {np.median(list(nse_hbv.values())):6.3f} | {np.median(list(nse_lstm.values())):6.3f}"
    for s in [2, 5, 10]:
        row += f" | {np.median(list(nse_tango[s].values())):6.3f}"
    print(row)

    print()
    for s in [2, 5, 10]:
        vs_l = sum(1 for b in BASINS if nse_tango[s][b] > nse_lstm[b])
        vs_h = sum(1 for b in BASINS if nse_tango[s][b] > nse_hbv[b])
        print(f"TANGO-{s} wins vs LSTM: {vs_l}/8, vs HBV: {vs_h}/8")


if __name__ == "__main__":
    main()
