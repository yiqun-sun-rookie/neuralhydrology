import numpy as np
import pandas as pd


def compute_metrics(obs: pd.Series, sim: pd.Series) -> dict:
    aligned = pd.concat([obs.rename("obs"), sim.rename("sim")], axis=1).dropna()
    if aligned.empty:
        raise ValueError("Observed and simulated discharge do not overlap.")

    obs_values = aligned["obs"].to_numpy(dtype=float)
    sim_values = aligned["sim"].to_numpy(dtype=float)
    if not np.isfinite(obs_values).all() or not np.isfinite(sim_values).all():
        raise ValueError("Non-finite discharge encountered during metric computation.")

    nse = _compute_nse(obs_values, sim_values)
    kge = _compute_kge(obs_values, sim_values)
    mean_obs = float(np.mean(obs_values))
    bias = float(np.mean(sim_values - obs_values) / mean_obs) if mean_obs != 0 else np.nan

    peak_mask = obs_values >= np.quantile(obs_values, 0.8)
    low_mask = obs_values <= np.quantile(obs_values, 0.2)
    peak_bias = _relative_bias(obs_values[peak_mask], sim_values[peak_mask])
    lowflow_bias = _relative_bias(obs_values[low_mask], sim_values[low_mask])

    return {
        "nse": round(nse, 6),
        "kge": round(kge, 6),
        "bias": round(bias, 6),
        "peak_bias": round(peak_bias, 6),
        "lowflow_bias": round(lowflow_bias, 6),
    }


def _compute_nse(obs_values: np.ndarray, sim_values: np.ndarray) -> float:
    denominator = np.sum((obs_values - np.mean(obs_values)) ** 2)
    if denominator <= 0:
        return np.nan
    numerator = np.sum((sim_values - obs_values) ** 2)
    return float(1.0 - numerator / denominator)


def _compute_kge(obs_values: np.ndarray, sim_values: np.ndarray) -> float:
    if len(obs_values) <= 1:
        corr = 1.0
    elif np.std(obs_values) == 0 or np.std(sim_values) == 0:
        corr = np.nan
    else:
        corr = np.corrcoef(obs_values, sim_values)[0, 1]
    alpha = np.std(sim_values) / np.std(obs_values) if np.std(obs_values) > 0 else np.nan
    beta = np.mean(sim_values) / np.mean(obs_values) if np.mean(obs_values) != 0 else np.nan
    return float(1.0 - np.sqrt((corr - 1.0) ** 2 + (alpha - 1.0) ** 2 + (beta - 1.0) ** 2))


def _relative_bias(obs_values: np.ndarray, sim_values: np.ndarray) -> float:
    if len(obs_values) == 0:
        return np.nan
    mean_obs = float(np.mean(obs_values))
    if mean_obs == 0:
        return np.nan
    return float(np.mean(sim_values - obs_values) / mean_obs)
