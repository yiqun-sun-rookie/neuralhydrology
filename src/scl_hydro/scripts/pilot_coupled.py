"""Coupled LSTM-HBV Pilot v3: Residual architecture.

E1: Pure HBV (fixed calibrated params)
E2: Pure LSTM (normalized, direct Q prediction)
E3: Coupled = HBV(fixed) + LSTM residual + physical state feedback

Usage:
    cd G:/github/pycharm/projects/neuralhydrology/src
    python -u -m scl_hydro.scripts.pilot_coupled [--epochs N]
"""
import argparse
import sys
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from scl_hydro.data_utils import load_camels_basins
from scl_hydro.hbv_torch import DifferentiableHBV, PARAM_NAMES
from scl_hydro.coupled_model import CoupledHydroModel

DEFAULT_DATA_DIR = Path(__file__).parent.parent.parent.parent / "data" / "camels_us"
BASINS = ["01013500", "01022500", "09035900"]

TRAIN_START, TRAIN_END = "1999-10-01", "2008-09-30"
TEST_START, TEST_END = "1989-10-01", "1999-09-30"

CAMELS_FEATURES = ["prcp(mm/day)", "srad(W/m2)", "tmax(C)", "tmin(C)", "vp(Pa)"]
TARGET = "QObs(mm/d)"
HIDDEN_SIZE = 64
SEG_LENGTH = 180
BATCH_SIZE = 8
LR = 0.001


def make_forcing_df(df):
    """Add PET and Tmean columns, return forcing col names."""
    srad = df["srad(W/m2)"].values
    tmax, tmin = df["tmax(C)"].values, df["tmin(C)"].values
    df["pet(mm/d)"] = np.maximum(0, 0.65 * srad * 0.0864 / 2.45).astype(np.float32)
    df["tmean(C)"] = ((tmax + tmin) / 2).astype(np.float32)
    return df


# HBV forcing: (rain, pet, temp) = columns (0, 1, 2)
HBV_FORCING_COLS = ["prcp(mm/day)", "pet(mm/d)", "tmean(C)"]
# Extra LSTM features on top of HBV forcing
ALL_FORCING_COLS = ["prcp(mm/day)", "pet(mm/d)", "tmean(C)", "srad(W/m2)", "vp(Pa)"]


def nse(obs, sim):
    m = np.isfinite(obs) & np.isfinite(sim)
    o, s = obs[m], sim[m]
    if len(o) < 10: return float("nan")
    ss = np.sum((s - o) ** 2)
    st = np.sum((o - o.mean()) ** 2)
    return float(1 - ss / st) if st > 0 else float("nan")


def build_segments(data, forcing_cols, target_col, seg_length):
    forcings, targets = [], []
    for _, df in data.items():
        f = df[forcing_cols].values.astype(np.float32)
        t = df[[target_col]].values.astype(np.float32)
        for start in range(0, len(f) - seg_length, seg_length // 2):
            sf, st = f[start:start + seg_length], t[start:start + seg_length]
            if not np.any(np.isnan(st)):
                forcings.append(sf); targets.append(st)
    return np.array(forcings), np.array(targets)


def calibrate_hbv_per_basin(data, target_col):
    """Calibrate HBV per basin with L-BFGS. Returns dict of param dicts."""
    hbv = DifferentiableHBV()
    calibrated = {}

    for basin_id, df in data.items():
        rain = df["prcp(mm/day)"].values
        pet = df["pet(mm/d)"].values
        tmean = df["tmean(C)"].values
        q_obs = df[target_col].values

        forcing = torch.tensor(np.stack([rain, pet, tmean], axis=-1)[np.newaxis], dtype=torch.float32)
        q_target = torch.tensor(q_obs[np.newaxis, :, np.newaxis], dtype=torch.float32)
        mask = ~torch.isnan(q_target)

        raw = torch.zeros(1, 10, requires_grad=True)
        opt = torch.optim.LBFGS([raw], lr=0.3, max_iter=20, line_search_fn="strong_wolfe")

        for _ in range(30):
            def closure():
                opt.zero_grad()
                p = hbv.constrain_params(raw)
                _, q_raw, _ = hbv(forcing, p)
                loss = nn.functional.mse_loss(q_raw[mask], q_target[mask])
                loss.backward()
                return loss
            opt.step(closure)

        with torch.no_grad():
            p = hbv.constrain_params(raw)
            _, q_raw, _ = hbv(forcing, p)
            q_sim = q_raw[0, :, 0].numpy()
            train_nse = nse(q_obs, q_sim)

        params = {name: p[name][0, 0].item() for name in PARAM_NAMES}
        calibrated[basin_id] = params
        print(f"  {basin_id}: train NSE={train_nse:.4f}  "
              f"Smax={params['Smax']:.1f} Ce={params['Ce']:.3f} beta={params['beta']:.2f}")

    return calibrated


def eval_hbv(calibrated_params, test_data, target_col):
    """Evaluate calibrated HBV on test data."""
    hbv = DifferentiableHBV()
    results = {}
    for basin_id, df in test_data.items():
        forcing = torch.tensor(np.stack([
            df["prcp(mm/day)"].values,
            df["pet(mm/d)"].values,
            df["tmean(C)"].values,
        ], axis=-1)[np.newaxis], dtype=torch.float32)
        params = hbv.dict_from_values(calibrated_params[basin_id])
        with torch.no_grad():
            _, q_raw, _ = hbv(forcing, params)
        results[basin_id] = nse(df[target_col].values, q_raw[0, :, 0].numpy())
    return results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--data-dir", type=str, default=str(DEFAULT_DATA_DIR))
    parser.add_argument("--epochs", type=int, default=50)
    args = parser.parse_args()

    data_dir = Path(args.data_dir)
    print(f"=== Coupled LSTM-HBV Pilot v3 (Residual Architecture) ===")
    print(f"Basins: {BASINS}, Epochs: {args.epochs}, hidden={HIDDEN_SIZE}")
    print()

    # Load data
    train_raw = load_camels_basins(data_dir, BASINS, CAMELS_FEATURES, TARGET, TRAIN_START, TRAIN_END)
    test_raw = load_camels_basins(data_dir, BASINS, CAMELS_FEATURES, TARGET, TEST_START, TEST_END)
    for d in [train_raw, test_raw]:
        for _, df in d.items():
            make_forcing_df(df)

    # ================================================================
    # E1: Calibrate pure HBV per basin
    # ================================================================
    print("--- E1: Pure HBV (L-BFGS per-basin calibration) ---")
    t0 = time.time()
    cal_params = calibrate_hbv_per_basin(train_raw, TARGET)
    print(f"  Time: {time.time() - t0:.0f}s")
    nse_e1 = eval_hbv(cal_params, test_raw, TARGET)

    # Build segments for LSTM-based models
    train_f, train_t = build_segments(train_raw, ALL_FORCING_COLS, TARGET, SEG_LENGTH)
    n_forcing = len(ALL_FORCING_COLS)
    print(f"\nSegments: {len(train_f)}")

    # Compute scaler
    flat_f = train_f.reshape(-1, n_forcing)
    f_mean = np.nanmean(flat_f, axis=0).astype(np.float32)
    f_std = np.nanstd(flat_f, axis=0).astype(np.float32)
    f_std[f_std < 1e-6] = 1.0
    flat_t = train_t.reshape(-1, 1)
    t_mean = np.nanmean(flat_t).astype(np.float32)
    t_std = np.nanstd(flat_t).astype(np.float32)

    # ================================================================
    # E2: Pure LSTM (normalized)
    # ================================================================
    print(f"\n--- E2: Pure LSTM (z-score normalized) ---")
    torch.manual_seed(42)
    train_f_norm = (train_f - f_mean) / f_std
    train_t_norm = (train_t - t_mean) / t_std

    lstm = nn.LSTM(input_size=n_forcing, hidden_size=HIDDEN_SIZE, batch_first=True)
    head = nn.Linear(HIDDEN_SIZE, 1)
    all_p = list(lstm.parameters()) + list(head.parameters())
    opt = torch.optim.Adam(all_p, lr=LR)

    ds = torch.utils.data.TensorDataset(torch.tensor(train_f_norm), torch.tensor(train_t_norm))
    loader = torch.utils.data.DataLoader(ds, batch_size=BATCH_SIZE, shuffle=True, drop_last=True)

    t0 = time.time()
    for epoch in range(args.epochs):
        lstm.train(); head.train()
        losses = []
        for fb, tb in loader:
            out = head(lstm(fb)[0])
            m = ~torch.isnan(tb)
            if m.sum() == 0: continue
            loss = nn.functional.mse_loss(out[m], tb[m])
            opt.zero_grad(); loss.backward()
            nn.utils.clip_grad_norm_(all_p, 1.0); opt.step()
            losses.append(loss.item())
        if losses and ((epoch + 1) % 10 == 0 or epoch == 0):
            print(f"  Epoch {epoch+1:3d}: loss={np.mean(losses):.4f}")
    print(f"  Time: {time.time() - t0:.0f}s")

    # Eval E2
    lstm.eval(); head.eval()
    nse_e2 = {}
    with torch.no_grad():
        for basin_id, df in test_raw.items():
            f_raw = df[ALL_FORCING_COLS].values.astype(np.float32)
            t_raw = df[TARGET].values
            preds, obs = [], []
            for start in range(0, len(f_raw) - SEG_LENGTH, SEG_LENGTH):
                sf = (f_raw[start:start + SEG_LENGTH] - f_mean) / f_std
                ft = torch.tensor(sf[np.newaxis])
                q_norm = head(lstm(ft)[0])[0, :, 0].numpy()
                preds.append(q_norm * t_std + t_mean)
                obs.append(t_raw[start:start + SEG_LENGTH])
            if preds:
                nse_e2[basin_id] = nse(np.concatenate(obs), np.concatenate(preds))

    # ================================================================
    # E3: Coupled HBV(fixed) + LSTM residual
    # ================================================================
    print(f"\n--- E3: Coupled HBV + LSTM residual ---")

    # Use average calibrated params for multi-basin coupled model
    avg_params = {}
    for name in PARAM_NAMES:
        avg_params[name] = float(np.mean([cal_params[b][name] for b in BASINS]))
    print(f"  Avg HBV params: Smax={avg_params['Smax']:.1f} Ce={avg_params['Ce']:.3f}")

    torch.manual_seed(42)
    model = CoupledHydroModel(
        n_forcing=n_forcing, hidden_size=HIDDEN_SIZE, hbv_params=avg_params,
        forcing_mean=torch.tensor(f_mean), forcing_std=torch.tensor(f_std),
    )
    opt3 = torch.optim.Adam(model.parameters(), lr=LR)

    ds3 = torch.utils.data.TensorDataset(torch.tensor(train_f), torch.tensor(train_t))
    loader3 = torch.utils.data.DataLoader(ds3, batch_size=BATCH_SIZE, shuffle=True, drop_last=True)

    t0 = time.time()
    for epoch in range(args.epochs):
        model.train()
        losses, corr_mags = [], []
        for fb, tb in loader3:
            out = model(fb)
            m = ~torch.isnan(tb)
            if m.sum() == 0: continue
            loss = nn.functional.mse_loss(out["y_hat"][m], tb[m])
            if torch.isnan(loss): continue
            opt3.zero_grad(); loss.backward()
            nn.utils.clip_grad_norm_(model.parameters(), 1.0); opt3.step()
            losses.append(loss.item())
            corr_mags.append(out["corrections"].abs().mean().item())
        if losses and ((epoch + 1) % 10 == 0 or epoch == 0):
            print(f"  Epoch {epoch+1:3d}: loss={np.mean(losses):.4f}  "
                  f"|Δstate|={np.mean(corr_mags):.4f}")
    print(f"  Time: {time.time() - t0:.0f}s")

    # Eval E3
    model.eval()
    nse_e3 = {}
    with torch.no_grad():
        for basin_id, df in test_raw.items():
            f_raw = df[ALL_FORCING_COLS].values.astype(np.float32)
            t_raw = df[TARGET].values
            preds, obs = [], []
            for start in range(0, len(f_raw) - SEG_LENGTH, SEG_LENGTH):
                ft = torch.tensor(f_raw[start:start + SEG_LENGTH][np.newaxis])
                out = model(ft)
                preds.append(out["y_hat"][0, :, 0].numpy())
                obs.append(t_raw[start:start + SEG_LENGTH])
            if preds:
                nse_e3[basin_id] = nse(np.concatenate(obs), np.concatenate(preds))

    # ================================================================
    # Results
    # ================================================================
    print(f"\n{'='*68}")
    print(f"{'Basin':>12s} | {'E1:HBV':>8s} | {'E2:LSTM':>8s} | {'E3:Coupled':>10s} | {'E3-E1':>7s} | {'E3-E2':>7s}")
    print(f"{'-'*12}-+-{'-'*8}-+-{'-'*8}-+-{'-'*10}-+-{'-'*7}-+-{'-'*7}")
    for b in BASINS:
        n1 = nse_e1.get(b, float("nan"))
        n2 = nse_e2.get(b, float("nan"))
        n3 = nse_e3.get(b, float("nan"))
        print(f"{b:>12s} | {n1:8.4f} | {n2:8.4f} | {n3:10.4f} | {n3-n1:+7.4f} | {n3-n2:+7.4f}")

    v1 = [v for v in nse_e1.values() if np.isfinite(v)]
    v2 = [v for v in nse_e2.values() if np.isfinite(v)]
    v3 = [v for v in nse_e3.values() if np.isfinite(v)]
    print(f"{'-'*12}-+-{'-'*8}-+-{'-'*8}-+-{'-'*10}-+-{'-'*7}-+-{'-'*7}")
    print(f"{'Mean':>12s} | {np.mean(v1):8.4f} | {np.mean(v2):8.4f} | {np.mean(v3):10.4f} | "
          f"{np.mean(v3)-np.mean(v1):+7.4f} | {np.mean(v3)-np.mean(v2):+7.4f}")


if __name__ == "__main__":
    main()
