"""TANGO multi-variable constraint: Q + SWE loss.

Per-basin comparison:
  E1: Pure HBV
  E2: Pure LSTM (Q only)
  E3: TANGO (Q only)
  E4: TANGO (Q + SWE constraint)

SWE data from CAMELS SAC-SMA/Snow-17 model output.
"""
import sys
import zipfile
from pathlib import Path

import numpy as np
import pandas as pd
import torch
import torch.nn as nn

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from scl_hydro.hbv_torch import DifferentiableHBV, PARAM_NAMES
from scl_hydro.coupled_model import CoupledHydroModel
from scl_hydro.data_utils import load_camels_basins

DATA_DIR = Path(__file__).parent.parent.parent.parent / "data" / "camels_us"
ZIP_PATH = DATA_DIR / "raw" / "basin_timeseries_v1p2_modelOutput_daymet.zip"

# Use snow-dominated basins where SWE matters
BASINS = ["01013500", "09035900", "12010000", "07056000"]
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


def load_swe(basin, start_date, end_date):
    """Load SWE time series from CAMELS model output zip."""
    zf = zipfile.ZipFile(ZIP_PATH)
    # Try all model variants, pick first available
    huc = basin[:2]
    candidates = [n for n in zf.namelist()
                  if f"/{huc}/{basin}_" in n and "model_output.txt" in n
                  and "__MACOSX" not in n]
    if not candidates:
        zf.close()
        return None

    with zf.open(candidates[0]) as f:
        df = pd.read_csv(f, sep=r"\s+")
    zf.close()

    df["date"] = pd.to_datetime(
        df["YR"].astype(str) + "/" + df["MNTH"].astype(str) + "/" + df["DY"].astype(str))
    df = df.set_index("date")
    df = df[start_date:end_date]
    return df["SWE"].values.astype(np.float32)


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

    # Load SWE
    swe_train = load_swe(basin, "1999-10-01", "2008-09-30")
    swe_test = load_swe(basin, "1989-10-01", "1999-09-30")

    f_tr = train[fcols].values.astype(np.float32)
    t_tr = train[[TARGET]].values.astype(np.float32)
    f_mean = f_tr.mean(0)
    f_std = f_tr.std(0)
    f_std[f_std < 1e-6] = 1
    t_mean = float(np.nanmean(t_tr))
    t_std = float(np.nanstd(t_tr))

    # Build segments with SWE
    segs_f, segs_t, segs_swe = [], [], []
    n = min(len(f_tr), len(swe_train)) if swe_train is not None else len(f_tr)
    for start in range(0, n - SEG, SEG // 2):
        sf = f_tr[start:start + SEG]
        st = t_tr[start:start + SEG]
        if not np.any(np.isnan(st)):
            segs_f.append(sf)
            segs_t.append(st)
            if swe_train is not None:
                segs_swe.append(swe_train[start:start + SEG])

    return (train, test, fcols, np.array(segs_f), np.array(segs_t),
            np.array(segs_swe) if segs_swe else None,
            f_mean, f_std, t_mean, t_std,
            swe_train, swe_test)


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
    return cal, s_mean, s_std, float(q.mean()), max(float(q.std()), 0.5)


def train_tango(segs_f, segs_t, segs_swe, cal, f_mean, f_std, s_mean, s_std, q_m, q_s,
                use_swe_loss=False, swe_weight=0.01):
    """Train TANGO, optionally with SWE auxiliary loss."""
    torch.manual_seed(42)
    sf_t = torch.tensor(segs_f)
    st_t = torch.tensor(segs_t)
    swe_t = torch.tensor(segs_swe[:, :, np.newaxis]) if segs_swe is not None else None

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

            loss_q = nn.functional.mse_loss(out["y_hat"][m], st_t[bi][m])

            if use_swe_loss and swe_t is not None:
                # S_snow is state index 0; out is already for this batch
                s_snow_pred = out["phys_states"][:, :, 0:1]
                swe_obs = swe_t[bi]
                swe_mask = swe_obs >= 0  # all valid
                loss_swe = nn.functional.mse_loss(s_snow_pred[swe_mask], swe_obs[swe_mask])
                loss = loss_q + swe_weight * loss_swe
            else:
                loss = loss_q

            if torch.isnan(loss):
                continue
            opt.zero_grad()
            loss.backward()
            nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            opt.step()

    return model


def eval_tango(model, test, fcols, swe_test=None):
    model.eval()
    f_te = test[fcols].values.astype(np.float32)
    preds_q, preds_snow, obs_q = [], [], []
    with torch.no_grad():
        for start in range(0, len(f_te) - SEG, SEG):
            out = model(torch.tensor(f_te[start:start + SEG][np.newaxis]))
            preds_q.append(out["y_hat"][0, :, 0].numpy())
            preds_snow.append(out["phys_states"][0, :, 0].numpy())
            obs_q.append(test[TARGET].values[start:start + SEG])

    nse_q = nse(np.concatenate(obs_q), np.concatenate(preds_q))

    # SWE correlation if available
    nse_swe = float("nan")
    if swe_test is not None:
        pred_snow_all = np.concatenate(preds_snow)
        swe_obs = swe_test[:len(pred_snow_all)]
        nse_swe = nse(swe_obs, pred_snow_all)

    return nse_q, nse_swe


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
    preds, obs = [], []
    with torch.no_grad():
        for start in range(0, len(f_te) - SEG, SEG):
            sf = (f_te[start:start + SEG] - f_mean) / f_std
            q = head(lstm(torch.tensor(sf[np.newaxis]))[0])[0, :, 0].numpy()
            preds.append(q * t_std + t_mean)
            obs.append(test[TARGET].values[start:start + SEG])
    return nse(np.concatenate(obs), np.concatenate(preds))


def main():
    print("=== TANGO Multi-Variable Constraint (Q + SWE) ===\n")

    results = {}
    for basin in BASINS:
        print(f"--- {basin} ---")
        (train, test, fcols, segs_f, segs_t, segs_swe,
         f_mean, f_std, t_mean, t_std, swe_train, swe_test) = prep_basin(basin)

        has_swe = segs_swe is not None and segs_swe.max() > 0
        print(f"  Segments: {len(segs_f)}, SWE available: {has_swe}")
        if has_swe:
            print(f"  SWE range: [{segs_swe.min():.1f}, {segs_swe.max():.1f}]")

        # Calibrate HBV
        cal, s_mean, s_std, q_m, q_s = calibrate_hbv(train, fcols)

        # E1: Pure HBV
        hbv = DifferentiableHBV()
        f_te_t = torch.tensor(
            np.stack([test[c].values for c in fcols], axis=-1)[np.newaxis], dtype=torch.float32)
        p = hbv.dict_from_values(cal)
        with torch.no_grad():
            _, q_te, _ = hbv(f_te_t, p)
        nse_hbv = nse(test[TARGET].values, q_te[0, :, 0].numpy())

        # E2: Pure LSTM
        lstm, head = train_lstm(segs_f, segs_t, f_mean, f_std, t_mean, t_std)
        nse_lstm = eval_lstm(lstm, head, test, fcols, f_mean, f_std, t_mean, t_std)

        # E3: TANGO Q-only
        model_q = train_tango(segs_f, segs_t, segs_swe, cal, f_mean, f_std,
                              s_mean, s_std, q_m, q_s, use_swe_loss=False)
        nse_tango_q, swe_nse_q = eval_tango(model_q, test, fcols, swe_test)

        # E4: TANGO Q+SWE
        nse_tango_swe, swe_nse_swe = float("nan"), float("nan")
        if has_swe:
            model_swe = train_tango(segs_f, segs_t, segs_swe, cal, f_mean, f_std,
                                    s_mean, s_std, q_m, q_s, use_swe_loss=True, swe_weight=0.01)
            nse_tango_swe, swe_nse_swe = eval_tango(model_swe, test, fcols, swe_test)

        results[basin] = {
            "hbv": nse_hbv, "lstm": nse_lstm,
            "tango_q": nse_tango_q, "tango_swe": nse_tango_swe,
            "swe_q": swe_nse_q, "swe_swe": swe_nse_swe,
        }
        print(f"  HBV={nse_hbv:.4f}  LSTM={nse_lstm:.4f}  "
              f"TANGO(Q)={nse_tango_q:.4f}  TANGO(Q+SWE)={nse_tango_swe:.4f}")
        print(f"  SWE NSE: Q-only={swe_nse_q:.4f}  Q+SWE={swe_nse_swe:.4f}")

    # Summary
    print(f"\n{'=' * 80}")
    print(f"{'Basin':>12s} | {'HBV':>6s} | {'LSTM':>6s} | {'T(Q)':>6s} | {'T(Q+SWE)':>9s} | "
          f"{'SWE(Q)':>7s} | {'SWE(+)':>7s}")
    print(f"{'-' * 12}-+-{'-' * 6}-+-{'-' * 6}-+-{'-' * 6}-+-{'-' * 9}-+-{'-' * 7}-+-{'-' * 7}")
    for b in BASINS:
        r = results[b]
        print(f"{b:>12s} | {r['hbv']:6.3f} | {r['lstm']:6.3f} | {r['tango_q']:6.3f} | "
              f"{r['tango_swe']:9.3f} | {r['swe_q']:7.3f} | {r['swe_swe']:7.3f}")

    print("\nQ NSE: higher = better streamflow prediction")
    print("SWE NSE: higher = better snow state estimation (TANGO unique capability)")


if __name__ == "__main__":
    main()
