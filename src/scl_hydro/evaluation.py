"""Evaluation utilities for SCL-LSTM models."""
from typing import Dict, List, Tuple

import numpy as np
import pandas as pd
import torch

from scl_hydro.model import SCLCudaLSTM


def evaluate_basins(
    model: SCLCudaLSTM,
    test_data: Dict[str, pd.DataFrame],
    main_features: List[str],
    enc_features: List[str],
    target: str,
    context_length: int,
    seg_length: int,
    target_scaler: Tuple[float, float],
    device: str = "cpu",
    use_encoder: bool = True,
) -> Dict[str, float]:
    """Evaluate model on test data, return NSE per basin.

    Processes each basin in non-overlapping segments. If use_encoder is True,
    the encoder uses the preceding context_length days (including Q_obs)
    to produce initial states. Otherwise, LSTM starts from zero state.
    """
    model.eval()
    target_mean, target_std = target_scaler
    results = {}

    with torch.no_grad():
        for basin_id, df in test_data.items():
            main = df[main_features].values.astype(np.float32)
            enc = df[enc_features].values.astype(np.float32) if use_encoder else None
            target_raw = df[target].values.astype(np.float32)
            n = len(target_raw)

            predictions = []
            observations = []

            start_t = context_length if use_encoder else 0
            t = start_t
            while t + seg_length <= n:
                pred_x = torch.from_numpy(main[t:t + seg_length]).unsqueeze(0).to(device)

                if use_encoder:
                    ctx = torch.from_numpy(enc[t - context_length:t]).unsqueeze(0).to(device)
                    out = model(pred_x, ctx)
                else:
                    out = model(pred_x, context_data=None)

                y_hat = out["y_hat"].squeeze(0).cpu().numpy().flatten()

                # De-normalize prediction
                y_hat_denorm = y_hat * target_std + target_mean
                # De-normalize observation
                y_obs_denorm = target_raw[t:t + seg_length].flatten() * target_std + target_mean

                predictions.append(y_hat_denorm)
                observations.append(y_obs_denorm)
                t += seg_length

            if not predictions:
                results[basin_id] = float("nan")
                continue

            y_hat_all = np.concatenate(predictions)
            y_obs_all = np.concatenate(observations)

            # Remove NaN observations
            mask = ~np.isnan(y_obs_all) & ~np.isnan(y_hat_all)
            y_hat_clean = y_hat_all[mask]
            y_obs_clean = y_obs_all[mask]

            if len(y_obs_clean) > 10:
                ss_res = np.sum((y_hat_clean - y_obs_clean) ** 2)
                ss_tot = np.sum((y_obs_clean - np.mean(y_obs_clean)) ** 2)
                nse = 1.0 - ss_res / ss_tot if ss_tot > 0 else float("nan")
                results[basin_id] = float(nse)
            else:
                results[basin_id] = float("nan")

    return results
