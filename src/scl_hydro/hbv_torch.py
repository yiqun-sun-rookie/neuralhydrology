"""Differentiable HBV model in PyTorch.

Mirrors the NumPy HBV in ``hbv_camels_us_531.hbv_model`` exactly, but uses
PyTorch operations so gradients can flow through the entire simulation.

Structure: Snow → Soil → Fast (power) + Slow (linear) → Lag → Q

States (4): S_snow, S_soil, S_fast, S_slow
Parameters (10): t0, k_snow, Smax, Ce, beta, split, k_fast, alpha, k_slow, lag_time

⚠️ DISAMBIGUATION (see README_HBV_MODELS.md): this is the OLD 4-state/10-param HBV,
kept ONLY because the SCL-LSTM project (coupled_model.py CoupledHydroModel) uses it.
It is NOT the 531 benchmark / DA model — for those use HBV-lite (hbv_lite.py /
hbv_lite_numpy.py, 5 states / 13 params, median NSE 0.5995/0.6227). Do not confuse them.
"""
from typing import Dict, Optional, Tuple

import torch
import torch.nn as nn
import torch.nn.functional as F

PARAM_NAMES = ["t0", "k_snow", "Smax", "Ce", "beta", "split", "k_fast", "alpha", "k_slow", "lag_time"]

PARAM_BOUNDS = {
    "t0":       (-3.0,   3.0),
    "k_snow":   ( 0.5,   5.0),
    "Smax":     (50.0, 500.0),
    "Ce":       ( 0.3,   1.5),
    "beta":     ( 1.0,   5.0),
    "split":    ( 0.1,   0.9),
    "k_fast":   ( 0.001, 0.5),
    "alpha":    ( 1.0,   3.0),
    "k_slow":   ( 0.001, 0.1),
    "lag_time": ( 1.0,  10.0),
}

N_STATES = 4
N_PARAMS = 10
STATE_NAMES = ["S_snow", "S_soil", "S_fast", "S_slow"]


class DifferentiableHBV(nn.Module):
    """Differentiable HBV hydrological model.

    All operations use ``torch.where`` / ``torch.clamp`` instead of Python
    ``if`` / ``min`` / ``max`` so that the computation graph is preserved
    for back-propagation.

    Parameters
    ----------
    eps : float
        Small constant for numerical stability in power-law computations.
    """

    def __init__(self, eps: float = 1e-8):
        super().__init__()
        self.eps = eps
        self.N_PARAMS = N_PARAMS
        self.N_STATES = N_STATES

    # ------------------------------------------------------------------
    # Single-step interface (for bidirectional coupling)
    # ------------------------------------------------------------------

    def forward_step(
        self,
        state: torch.Tensor,
        rain: torch.Tensor,
        pet: torch.Tensor,
        temp: torch.Tensor,
        params: Dict[str, torch.Tensor],
    ) -> Tuple[torch.Tensor, torch.Tensor]:
        """Run one timestep of HBV.

        Args:
            state:  [B, 4] — (S_snow, S_soil, S_fast, S_slow)
            rain:   [B, 1] — precipitation [mm/d]
            pet:    [B, 1] — potential ET [mm/d]
            temp:   [B, 1] — mean temperature [°C]
            params: dict of [B, 1] tensors for each of the 10 parameters

        Returns:
            state_next: [B, 4] — updated states
            q_raw:      [B, 1] — instantaneous discharge (before lag)
        """
        S_snow = state[:, 0:1]
        S_soil = state[:, 1:2]
        S_fast = state[:, 2:3]
        S_slow = state[:, 3:4]

        t0     = params["t0"]
        k_snow = params["k_snow"]
        Smax   = params["Smax"]
        Ce     = params["Ce"]
        beta   = params["beta"]
        split  = params["split"]
        k_fast = params["k_fast"]
        alpha  = params["alpha"]
        k_slow = params["k_slow"]

        P   = rain
        PET = pet
        Tm  = temp

        # --- Snow module ---
        is_snow = (Tm < t0).float()
        snowfall = P * is_snow
        rainfall = P * (1.0 - is_snow)

        S_snow = S_snow + snowfall
        melt_potential = k_snow * torch.clamp(Tm - t0, min=0.0)
        melt = torch.minimum(melt_potential, S_snow)
        S_snow = S_snow - melt
        P_eff = rainfall + melt

        # --- Soil moisture ---
        s_ratio = torch.clamp(S_soil / (Smax + self.eps), min=0.0, max=1.0)
        # s_ratio ** beta with numerical safety
        recharge = P_eff * torch.pow(s_ratio + self.eps, beta)
        aet = Ce * PET * torch.clamp(s_ratio, max=1.0)
        S_soil = S_soil + P_eff - recharge - aet
        S_soil = torch.clamp(S_soil, min=0.0)
        S_soil = torch.minimum(S_soil, Smax)

        # --- Fast reservoir (power law) ---
        # q_fast = k_fast * S_fast^alpha, clamped to available water
        q_fast = k_fast * torch.pow(torch.clamp(S_fast, min=self.eps), alpha)
        available_fast = S_fast + split * recharge
        q_fast = torch.minimum(q_fast, torch.clamp(available_fast, min=0.0))
        S_fast = S_fast + split * recharge - q_fast
        S_fast = torch.clamp(S_fast, min=0.0)

        # --- Slow reservoir (linear) ---
        q_slow = k_slow * S_slow
        available_slow = S_slow + (1.0 - split) * recharge
        q_slow = torch.minimum(q_slow, torch.clamp(available_slow, min=0.0))
        S_slow = S_slow + (1.0 - split) * recharge - q_slow
        S_slow = torch.clamp(S_slow, min=0.0)

        q_raw = q_fast + q_slow
        state_next = torch.cat([S_snow, S_soil, S_fast, S_slow], dim=-1)
        return state_next, q_raw

    # ------------------------------------------------------------------
    # Full-sequence interface
    # ------------------------------------------------------------------

    def forward(
        self,
        forcing: torch.Tensor,
        params: Dict[str, torch.Tensor],
        state_init: Optional[torch.Tensor] = None,
    ) -> Tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
        """Run HBV over a full time series.

        Args:
            forcing:    [B, T, 3] — (rain, pet, temp) per timestep
            params:     dict of [B, 1] tensors (static params held constant)
            state_init: [B, 4] or None — initial states

        Returns:
            q_sim:      [B, T, 1] — simulated discharge (after lag)
            q_raw:      [B, T, 1] — discharge before lag
            states_all: [B, T, 4] — state trajectories
        """
        B, T, _ = forcing.shape
        device = forcing.device

        if state_init is None:
            Smax = params["Smax"]  # [B, 1]
            state = torch.cat([
                torch.zeros(B, 1, device=device),          # S_snow
                Smax * 0.3,                                 # S_soil
                torch.full((B, 1), 5.0, device=device),    # S_fast
                torch.full((B, 1), 5.0, device=device),    # S_slow
            ], dim=-1)
        else:
            state = state_init

        q_raw_list = []
        states_list = []

        for t in range(T):
            rain = forcing[:, t, 0:1]
            pet  = forcing[:, t, 1:2]
            temp = forcing[:, t, 2:3]
            state, q_t = self.forward_step(state, rain, pet, temp, params)
            q_raw_list.append(q_t)
            states_list.append(state)

        q_raw = torch.stack(q_raw_list, dim=1)     # [B, T, 1]
        states_all = torch.stack(states_list, dim=1)  # [B, T, 4]

        # Triangular lag routing
        lag_time = params["lag_time"]  # [B, 1]
        q_sim = self._triangular_lag_batch(q_raw, lag_time)

        return q_sim, q_raw, states_all

    def _triangular_lag_batch(self, q_raw: torch.Tensor, lag_time: torch.Tensor) -> torch.Tensor:
        """Apply half-triangular lag routing per basin.

        Args:
            q_raw:    [B, T, 1]
            lag_time: [B, 1]

        Returns:
            q_lagged: [B, T, 1]
        """
        B, T, _ = q_raw.shape
        q_out = torch.zeros_like(q_raw)

        for b in range(B):
            lt = lag_time[b, 0].item()
            n = max(int(torch.ceil(torch.tensor(lt)).item()), 1)
            weights = torch.arange(1, n + 1, dtype=torch.float32, device=q_raw.device)
            weights = weights / weights.sum()
            # 1D convolution: input [1, 1, T], kernel [1, 1, n]
            q_1d = q_raw[b, :, 0].unsqueeze(0).unsqueeze(0)  # [1, 1, T]
            kernel = weights.flip(0).unsqueeze(0).unsqueeze(0)  # [1, 1, n]
            pad = n - 1
            q_conv = F.conv1d(q_1d, kernel, padding=pad)[:, :, :T]  # [1, 1, T]
            q_out[b, :, 0] = q_conv.squeeze()

        return q_out

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    @staticmethod
    def constrain_params(raw: torch.Tensor) -> Dict[str, torch.Tensor]:
        """Map unconstrained [B, 10] to physically-bounded parameter dict.

        Uses sigmoid scaling to map (-inf, inf) → (lo, hi) for each parameter.
        """
        params = {}
        for i, name in enumerate(PARAM_NAMES):
            lo, hi = PARAM_BOUNDS[name]
            params[name] = torch.sigmoid(raw[:, i:i+1]) * (hi - lo) + lo
        return params

    @staticmethod
    def dict_from_values(values: Dict[str, float], batch_size: int = 1,
                         device: torch.device = None) -> Dict[str, torch.Tensor]:
        """Convert scalar param dict to batched tensor dict."""
        if device is None:
            device = torch.device("cpu")
        return {k: torch.full((batch_size, 1), v, dtype=torch.float32, device=device)
                for k, v in values.items()}

    def get_state_tensor(self, states: Dict[str, torch.Tensor]) -> torch.Tensor:
        """Dict → [B, 4] tensor."""
        return torch.cat([states[n] for n in STATE_NAMES], dim=-1)

    def set_state_from_tensor(self, x: torch.Tensor) -> Dict[str, torch.Tensor]:
        """[B, 4] tensor → dict."""
        return {STATE_NAMES[i]: x[:, i:i+1] for i in range(N_STATES)}
