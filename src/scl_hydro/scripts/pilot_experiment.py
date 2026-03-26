"""SCL-LSTM Pilot Experiment v2: 3-way comparison on 8 CAMELS basins.

Experiments:
  E1: Vanilla LSTM     — no encoder, h0=0, single segments, MSE
  E2: Encoder-only     — encoder → h0, single segments, MSE (no SCL)
  E3: SCL-LSTM         — encoder → h0, overlapping pairs, MSE + SCL

Usage:
    cd G:/github/pycharm/projects/neuralhydrology/src
    python -u -m scl_hydro.scripts.pilot_experiment [--epochs N]
"""
import argparse
import sys
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from scl_hydro.data_utils import load_camels_basins, compute_scaler, apply_scaler
from scl_hydro.dataset import SCLDataset, SingleSegDataset
from scl_hydro.evaluation import evaluate_basins
from scl_hydro.model import SCLCudaLSTM
from scl_hydro.trainer import SCLTrainer

# --- Configuration ---
BASINS_FILE = Path(__file__).parent.parent / "configs" / "pilot_8basins.txt"
DEFAULT_DATA_DIR = Path(__file__).parent.parent.parent.parent / "data" / "camels_us"

MAIN_FEATURES = ["prcp(mm/day)", "srad(W/m2)", "tmax(C)", "tmin(C)", "vp(Pa)"]
ENC_FEATURES = MAIN_FEATURES + ["QObs(mm/d)"]
TARGET = "QObs(mm/d)"

HIDDEN_SIZE = 64
ENC_HIDDEN_SIZE = 32
SEG_LENGTH = 60
CONTEXT_LENGTH = 15
OVERLAP_LENGTH = 15
BATCH_SIZE = 32
LR = 0.001

TRAIN_START = "1999-10-01"
TRAIN_END = "2008-09-30"
TEST_START = "1989-10-01"
TEST_END = "1999-09-30"


def load_basins_list(path: Path):
    with open(path) as f:
        return [line.strip() for line in f if line.strip()]


def train_single_seg(dataset, n_epochs, use_encoder, seed=42, label=""):
    """Train SCLCudaLSTM on single segments (E1 or E2).

    E1 (use_encoder=False): context_data=None → h0=0
    E2 (use_encoder=True):  context_data from dataset → encoder → h0
    """
    torch.manual_seed(seed)
    np.random.seed(seed)

    model = SCLCudaLSTM(
        n_main_features=len(MAIN_FEATURES),
        n_enc_features=len(ENC_FEATURES),
        hidden_size=HIDDEN_SIZE,
        enc_hidden_size=ENC_HIDDEN_SIZE,
        n_targets=1,
    )
    optimizer = torch.optim.Adam(model.parameters(), lr=LR)
    loss_fn = nn.MSELoss()
    loader = DataLoader(dataset, batch_size=BATCH_SIZE, shuffle=True, drop_last=True)

    for epoch in range(n_epochs):
        model.train()
        epoch_losses = []
        for batch in loader:
            x = batch["x"]       # [B, seg_len, n_main]
            y = batch["y"]       # [B, seg_len, 1]
            ctx = batch.get("context", None)  # [B, ctx_len, n_enc] or None

            if use_encoder and ctx is not None:
                out = model(x, ctx)
            else:
                out = model(x, context_data=None)

            loss = loss_fn(out["y_hat"], y)
            optimizer.zero_grad()
            loss.backward()
            nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            optimizer.step()
            epoch_losses.append(loss.item())

        if (epoch + 1) % 5 == 0 or epoch == 0:
            print(f"  [{label}] Epoch {epoch + 1:3d}/{n_epochs}: "
                  f"loss={np.mean(epoch_losses):.4f}")

    return model


def train_scl(dataset, n_epochs, seed=42):
    """Train SCLCudaLSTM with SCL loss on overlapping pairs (E3)."""
    torch.manual_seed(seed)
    np.random.seed(seed)

    model = SCLCudaLSTM(
        n_main_features=len(MAIN_FEATURES),
        n_enc_features=len(ENC_FEATURES),
        hidden_size=HIDDEN_SIZE,
        enc_hidden_size=ENC_HIDDEN_SIZE,
        n_targets=1,
    )

    trainer = SCLTrainer(
        model=model,
        dataset=dataset,
        scl_weight=0.1,
        overlap_start=SEG_LENGTH - OVERLAP_LENGTH,
        overlap_length=OVERLAP_LENGTH,
        lr=LR,
        batch_size=BATCH_SIZE,
    )

    steps_per_epoch = max(1, len(dataset) // BATCH_SIZE)

    for epoch in range(n_epochs):
        pred_losses, scl_losses = [], []
        for _ in range(steps_per_epoch):
            loss = trainer.train_step()
            pred_losses.append(loss["pred_loss"])
            scl_losses.append(loss["scl_loss"])

        if (epoch + 1) % 5 == 0 or epoch == 0:
            print(f"  [E3:SCL] Epoch {epoch + 1:3d}/{n_epochs}: "
                  f"pred={np.mean(pred_losses):.4f}  "
                  f"scl={np.mean(scl_losses):.4f}")

    return model


def main():
    parser = argparse.ArgumentParser(description="SCL-LSTM Pilot v2")
    parser.add_argument("--data-dir", type=str, default=str(DEFAULT_DATA_DIR))
    parser.add_argument("--epochs", type=int, default=20)
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    data_dir = Path(args.data_dir)
    basins = load_basins_list(BASINS_FILE)
    print(f"=== SCL-LSTM Pilot v2: 3-way comparison ===")
    print(f"Basins: {basins}")
    print(f"Epochs: {args.epochs}, hidden={HIDDEN_SIZE}, seg={SEG_LENGTH}, "
          f"ctx={CONTEXT_LENGTH}, overlap={OVERLAP_LENGTH}")
    print()

    # --- Load & normalize ---
    print("Loading data...")
    train_data = load_camels_basins(data_dir, basins, MAIN_FEATURES, TARGET, TRAIN_START, TRAIN_END)
    test_data = load_camels_basins(data_dir, basins, MAIN_FEATURES, TARGET, TEST_START, TEST_END)

    scaler = compute_scaler(train_data)
    train_norm = apply_scaler(train_data, scaler)
    test_norm = apply_scaler(test_data, scaler)
    target_scaler = scaler[TARGET]
    print(f"  Q scaler: mean={target_scaler[0]:.4f}, std={target_scaler[1]:.4f}")

    # --- Create datasets ---
    # E1: single segments, no context
    ds_single = SingleSegDataset(
        data=train_norm, seg_length=SEG_LENGTH,
        main_features=MAIN_FEATURES, target=TARGET,
    )
    # E2: single segments with encoder context
    ds_enc = SingleSegDataset(
        data=train_norm, seg_length=SEG_LENGTH,
        main_features=MAIN_FEATURES, target=TARGET,
        context_length=CONTEXT_LENGTH, enc_features=ENC_FEATURES,
    )
    # E3: overlapping pairs for SCL
    ds_scl = SCLDataset(
        data=train_norm, seg_length=SEG_LENGTH,
        context_length=CONTEXT_LENGTH, overlap_length=OVERLAP_LENGTH,
        main_features=MAIN_FEATURES, enc_features=ENC_FEATURES, target=TARGET,
    )
    print(f"  Datasets: E1={len(ds_single)}, E2={len(ds_enc)}, E3={len(ds_scl)} samples")

    # --- E1: Vanilla LSTM (no encoder, h0=0) ---
    print(f"\n--- E1: Vanilla LSTM (no encoder, h0=0) ---")
    t0 = time.time()
    model_e1 = train_single_seg(ds_single, args.epochs, use_encoder=False,
                                seed=args.seed, label="E1:Vanilla")
    t_e1 = time.time() - t0
    print(f"  Time: {t_e1:.1f}s")

    # --- E2: Encoder-only (encoder → h0, no SCL) ---
    print(f"\n--- E2: Encoder-only (no SCL loss) ---")
    t0 = time.time()
    model_e2 = train_single_seg(ds_enc, args.epochs, use_encoder=True,
                                seed=args.seed, label="E2:Enc-only")
    t_e2 = time.time() - t0
    print(f"  Time: {t_e2:.1f}s")

    # --- E3: SCL-LSTM (encoder + SCL loss) ---
    print(f"\n--- E3: SCL-LSTM (encoder + SCL λ=0.1) ---")
    t0 = time.time()
    model_e3 = train_scl(ds_scl, args.epochs, seed=args.seed)
    t_e3 = time.time() - t0
    print(f"  Time: {t_e3:.1f}s")

    # --- Evaluate all three ---
    print(f"\n--- Evaluating on test period ({TEST_START} to {TEST_END}) ---")
    nse_e1 = evaluate_basins(
        model_e1, test_norm, MAIN_FEATURES, ENC_FEATURES, TARGET,
        CONTEXT_LENGTH, SEG_LENGTH, target_scaler, use_encoder=False,
    )
    nse_e2 = evaluate_basins(
        model_e2, test_norm, MAIN_FEATURES, ENC_FEATURES, TARGET,
        CONTEXT_LENGTH, SEG_LENGTH, target_scaler, use_encoder=True,
    )
    nse_e3 = evaluate_basins(
        model_e3, test_norm, MAIN_FEATURES, ENC_FEATURES, TARGET,
        CONTEXT_LENGTH, SEG_LENGTH, target_scaler, use_encoder=True,
    )

    # --- Results table ---
    print(f"\n{'='*72}")
    print(f"{'Basin':>12s} | {'E1:Vanilla':>10s} | {'E2:Enc-only':>11s} | "
          f"{'E3:SCL':>10s} | {'E3-E1':>8s} | {'E3-E2':>8s}")
    print(f"{'-'*12}-+-{'-'*10}-+-{'-'*11}-+-{'-'*10}-+-{'-'*8}-+-{'-'*8}")

    for basin in basins:
        n1 = nse_e1.get(basin, float("nan"))
        n2 = nse_e2.get(basin, float("nan"))
        n3 = nse_e3.get(basin, float("nan"))
        print(f"{basin:>12s} | {n1:10.4f} | {n2:11.4f} | {n3:10.4f} | "
              f"{n3 - n1:+8.4f} | {n3 - n2:+8.4f}")

    vals_e1 = [nse_e1[b] for b in basins if not np.isnan(nse_e1.get(b, float("nan")))]
    vals_e2 = [nse_e2[b] for b in basins if not np.isnan(nse_e2.get(b, float("nan")))]
    vals_e3 = [nse_e3[b] for b in basins if not np.isnan(nse_e3.get(b, float("nan")))]
    print(f"{'-'*12}-+-{'-'*10}-+-{'-'*11}-+-{'-'*10}-+-{'-'*8}-+-{'-'*8}")
    med_e1, med_e2, med_e3 = np.median(vals_e1), np.median(vals_e2), np.median(vals_e3)
    mean_e1, mean_e2, mean_e3 = np.mean(vals_e1), np.mean(vals_e2), np.mean(vals_e3)
    print(f"{'Median':>12s} | {med_e1:10.4f} | {med_e2:11.4f} | {med_e3:10.4f} | "
          f"{med_e3 - med_e1:+8.4f} | {med_e3 - med_e2:+8.4f}")
    print(f"{'Mean':>12s} | {mean_e1:10.4f} | {mean_e2:11.4f} | {mean_e3:10.4f} | "
          f"{mean_e3 - mean_e1:+8.4f} | {mean_e3 - mean_e2:+8.4f}")

    e3_vs_e1 = sum(1 for b in basins if nse_e3.get(b, -999) > nse_e1.get(b, -999))
    e3_vs_e2 = sum(1 for b in basins if nse_e3.get(b, -999) > nse_e2.get(b, -999))
    print(f"\nSCL wins vs Vanilla: {e3_vs_e1}/{len(basins)} basins")
    print(f"SCL wins vs Enc-only: {e3_vs_e2}/{len(basins)} basins")
    print(f"Time: E1={t_e1:.0f}s, E2={t_e2:.0f}s, E3={t_e3:.0f}s")


if __name__ == "__main__":
    main()
