"""Adam multi-restart calibration for ``DifferentiableHBVLite``.

Improvements over the original (random N(0,1) init + lr=0.02 + max_norm=10):
- **Hand-picked init** at literature-median HBV-light params (Seibert 2005,
  Beck 2017) instead of randn. Different restarts perturb around this
  median rather than starting from random raw values that produce
  pathological initial parameters after sigmoid mapping.
- **lr=0.005** (was 0.02): smaller step for stability on harder basins.
- **max_norm=1.0** (was 10.0): stricter gradient clip prevents explosion.
- **NaN safe**: a single NaN epoch no longer breaks the whole restart;
  it only stops the loss-update but lets the next epoch retry.
"""
import math

import numpy as np
import torch

from .hbv_lite import (
    DifferentiableHBVLite,
    PARAM_NAMES,
    PARAM_BOUNDS,
    N_PARAMS,
    STATE_NAMES,
)

WARMUP_DAYS = 365


# Literature-typical HBV-light median values (Seibert 2005, Beck 2017).
# Used to seed raw_params so initial sigmoid-mapped parameters are
# physically reasonable rather than the random-tail values produced by
# raw_params = torch.randn(...).
_PARAM_MEDIAN_INIT: dict[str, float] = {
    "parTT":     0.0,
    "parCFMAX":  3.0,
    "parCFR":    0.05,
    "parCWH":    0.10,
    "parFC":     200.0,
    "parBETA":   2.0,
    "parLP":     0.7,
    "parK0":     0.3,
    "parK1":     0.1,
    "parUZL":    30.0,
    "parPERC":   1.5,
    "parK2":     0.02,
    "lag_time":  3.0,
}


def _median_raw_init() -> torch.Tensor:
    """Inverse-sigmoid the median init values to raw space.

    Solves p = sigmoid(raw) for raw given p = (target - lo) / (hi - lo).
    Returns a [1, N_PARAMS] tensor whose sigmoid-mapped values equal
    `_PARAM_MEDIAN_INIT` after `constrain_params`.
    """
    raw = torch.zeros(1, N_PARAMS, dtype=torch.float32)
    for i, name in enumerate(PARAM_NAMES):
        lo, hi = PARAM_BOUNDS[name]
        target = _PARAM_MEDIAN_INIT[name]
        p = (target - lo) / (hi - lo)
        p = min(max(p, 0.02), 0.98)  # avoid logit(0) / logit(1)
        raw[0, i] = math.log(p / (1.0 - p))
    return raw


def _nse_torch(obs: torch.Tensor, sim: torch.Tensor) -> torch.Tensor:
    mask = torch.isfinite(obs) & torch.isfinite(sim)
    if mask.sum() < 10:
        return torch.tensor(2.0)
    o = obs[mask]
    s = sim[mask]
    denom = ((o - o.mean()) ** 2).sum()
    if denom < 1e-12:
        return torch.tensor(2.0)
    return ((o - s) ** 2).sum() / denom


def calibrate_hbv_lite(
    rain: np.ndarray,
    pet: np.ndarray,
    temp: np.ndarray,
    obs: np.ndarray,
    n_epochs: int = 300,
    lr: float = 0.005,
    n_restarts: int = 5,
    state_init: dict | None = None,
    init_jitter: float = 1.0,
    grad_clip: float = 1.0,
) -> dict:
    """Adam multi-restart calibration. Returns dict with nse / optimized_params /
    qsim / final_state."""
    warmup = min(WARMUP_DAYS, len(obs) // 4)

    forcing = torch.tensor(
        np.stack([rain, pet, temp], axis=-1)[np.newaxis, :, :],
        dtype=torch.float32,
    )
    obs_tensor = torch.tensor(obs[warmup:], dtype=torch.float32)

    model = DifferentiableHBVLite()
    if state_init is not None:
        state_init_tensor = torch.tensor(
            [[state_init[n] for n in STATE_NAMES]],
            dtype=torch.float32,
        )
    else:
        state_init_tensor = None

    best_overall: tuple[torch.Tensor, float] | None = None
    median_init = _median_raw_init()  # [1, N_PARAMS]

    for restart in range(n_restarts):
        torch.manual_seed(restart * 1000 + 42)
        # Hand-picked init + Gaussian jitter (restart 0 = exact median, others perturbed)
        if restart == 0:
            raw_params = median_init.clone().requires_grad_(True)
        else:
            raw_params = (median_init + init_jitter * torch.randn(1, N_PARAMS)).clone().requires_grad_(True)
        optimizer  = torch.optim.Adam([raw_params], lr=lr)

        best_loss_this = float("inf")
        best_raw_this: torch.Tensor | None = None
        n_nan_in_row = 0

        for epoch in range(n_epochs):
            optimizer.zero_grad()
            params = model.constrain_params(raw_params)
            q_sim, _, _ = model.forward(forcing, params, state_init=state_init_tensor)
            q_eval = q_sim[0, warmup:, 0]
            loss = _nse_torch(obs_tensor, q_eval)

            if not torch.isfinite(loss):
                # NaN-safe: tolerate a few NaN epochs but stop if persistent
                n_nan_in_row += 1
                if n_nan_in_row >= 5:
                    break
                continue
            n_nan_in_row = 0

            loss.backward()
            torch.nn.utils.clip_grad_norm_([raw_params], max_norm=grad_clip)
            optimizer.step()

            loss_val = loss.item()
            if loss_val < best_loss_this:
                best_loss_this = loss_val
                best_raw_this  = raw_params.detach().clone()

        if best_raw_this is not None:
            if best_overall is None or best_loss_this < best_overall[1]:
                best_overall = (best_raw_this, best_loss_this)

    if best_overall is None:
        return {
            "nse": -999.0,
            "optimized_params": {},
            "qsim": np.zeros(len(obs)),
            "final_state": None,
        }

    with torch.no_grad():
        params = model.constrain_params(best_overall[0])
        q_sim, _, states = model.forward(forcing, params, state_init=state_init_tensor)

    q_np = q_sim[0, :, 0].numpy()
    best_nse = 1.0 - best_overall[1]

    best_params = {}
    for i, name in enumerate(PARAM_NAMES):
        lo, hi = PARAM_BOUNDS[name]
        val = torch.sigmoid(best_overall[0][0, i]).item() * (hi - lo) + lo
        best_params[name] = val

    final_state = {n: states[0, -1, i].item() for i, n in enumerate(STATE_NAMES)}

    return {
        "nse": float(best_nse),
        "optimized_params": best_params,
        "qsim": np.maximum(q_np, 0.0),
        "final_state": final_state,
    }


def simulate_hbv_lite(
    rain: np.ndarray,
    pet: np.ndarray,
    temp: np.ndarray,
    params: dict,
    state_init: dict | None = None,
) -> tuple[np.ndarray, dict]:
    """Forward run with given parameters (no calibration)."""
    forcing = torch.tensor(
        np.stack([rain, pet, temp], axis=-1)[np.newaxis, :, :],
        dtype=torch.float32,
    )
    if state_init is not None:
        state_init_tensor = torch.tensor(
            [[state_init[n] for n in STATE_NAMES]],
            dtype=torch.float32,
        )
    else:
        state_init_tensor = None

    model = DifferentiableHBVLite()
    params_dict = model.dict_from_values(params, batch_size=1)
    with torch.no_grad():
        q_sim, _, states = model.forward(forcing, params_dict, state_init=state_init_tensor)
    q_np = q_sim[0, :, 0].numpy()
    final_state = {n: states[0, -1, i].item() for i, n in enumerate(STATE_NAMES)}
    return np.maximum(q_np, 0.0), final_state
