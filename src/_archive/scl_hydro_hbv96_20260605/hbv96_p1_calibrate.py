"""Adam multi-restart calibration for ``DifferentiableHBV96P1``.

Mirrors ``calibrate_hbv_torch`` but uses the P1 model class and its
own ``PARAM_NAMES`` / ``PARAM_BOUNDS`` (11 parameters instead of 10).
"""
import numpy as np
import torch

from .hbv96_p1 import (
    DifferentiableHBV96P1,
    PARAM_NAMES,
    PARAM_BOUNDS,
    N_PARAMS,
    STATE_NAMES,
)

WARMUP_DAYS = 365


def _nse_torch(obs: torch.Tensor, sim: torch.Tensor) -> torch.Tensor:
    """Differentiable NSE loss (returns 1 - NSE for minimization)."""
    mask = torch.isfinite(obs) & torch.isfinite(sim)
    if mask.sum() < 10:
        return torch.tensor(2.0)
    o = obs[mask]
    s = sim[mask]
    denom = ((o - o.mean()) ** 2).sum()
    if denom < 1e-12:
        return torch.tensor(2.0)
    return ((o - s) ** 2).sum() / denom


def calibrate_hbv96_p1(
    rain: np.ndarray,
    pet: np.ndarray,
    temp: np.ndarray,
    obs: np.ndarray,
    n_epochs: int = 300,
    lr: float = 0.01,
    n_restarts: int = 5,
    n_substep: int = 4,
    state_init: dict | None = None,
) -> dict:
    """Adam multi-restart calibration of HBV-96 P1.

    Parameters
    ----------
    rain, pet, temp, obs : np.ndarray (1D, length T)
        Daily forcing and observed discharge (mm/d).
    n_epochs : int
        Adam steps per restart.
    lr : float
        Adam learning rate (on the unconstrained raw parameters).
    n_restarts : int
        Number of independent random initializations; best is returned.
    n_substep : int
        Sub-step count inside the HBV step (passed to model constructor).
    state_init : dict | None
        Optional initial state dict (S_snow, S_soil, S_uz, S_lz).

    Returns
    -------
    dict with keys: ``nse``, ``optimized_params``, ``qsim``, ``final_state``.
    """
    warmup = min(WARMUP_DAYS, len(obs) // 4)
    forcing = torch.tensor(
        np.stack([rain, pet, temp], axis=-1)[np.newaxis, :, :],
        dtype=torch.float32,
    )
    obs_tensor = torch.tensor(obs[warmup:], dtype=torch.float32)

    model = DifferentiableHBV96P1(n_substep=n_substep)
    if state_init is not None:
        state_init_tensor = torch.tensor(
            [[state_init[n] for n in STATE_NAMES]],
            dtype=torch.float32,
        )
    else:
        state_init_tensor = None

    best_overall: tuple[torch.Tensor, float] | None = None

    for restart in range(n_restarts):
        torch.manual_seed(restart * 1000 + 42)
        raw_params = torch.randn(1, N_PARAMS, requires_grad=True)
        optimizer = torch.optim.Adam([raw_params], lr=lr)

        best_loss_this = float("inf")
        best_raw_this: torch.Tensor | None = None

        for epoch in range(n_epochs):
            optimizer.zero_grad()
            params = model.constrain_params(raw_params)
            q_sim, _, _ = model.forward(forcing, params, state_init=state_init_tensor)
            q_eval = q_sim[0, warmup:, 0]
            loss = _nse_torch(obs_tensor, q_eval)

            if not torch.isfinite(loss):
                break

            loss.backward()
            torch.nn.utils.clip_grad_norm_([raw_params], max_norm=10.0)
            optimizer.step()

            loss_val = loss.item()
            if loss_val < best_loss_this:
                best_loss_this = loss_val
                best_raw_this = raw_params.detach().clone()

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


def simulate_hbv96_p1(
    rain: np.ndarray,
    pet: np.ndarray,
    temp: np.ndarray,
    params: dict,
    state_init: dict | None = None,
    n_substep: int = 4,
) -> tuple[np.ndarray, dict]:
    """Forward run of HBV-96 P1 with given parameters (no calibration).

    Mirrors the signature of ``hbv_model.simulate_hbv`` so it can be
    used in the same train→eval state-propagation pattern.
    """
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

    model = DifferentiableHBV96P1(n_substep=n_substep)
    params_dict = model.dict_from_values(params, batch_size=1)
    with torch.no_grad():
        q_sim, _, states = model.forward(forcing, params_dict, state_init=state_init_tensor)
    q_np = q_sim[0, :, 0].numpy()
    final_state = {n: states[0, -1, i].item() for i, n in enumerate(STATE_NAMES)}
    return np.maximum(q_np, 0.0), final_state
