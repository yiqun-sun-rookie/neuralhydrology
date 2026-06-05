"""Differentiable HBV-96 (P1 variant) in PyTorch.

Upgrade over ``DifferentiableHBV`` in ``hbv_torch.py``:

  - Upper zone with **double outlet + threshold** (K0 above UZL, K1 always-on)
  - **Cascade** routing: UZ feeds LZ via percolation (PERC),
    replacing the previous parallel split partition.
  - **Sub-step** explicit Euler integration (default dt=1/4) for numerical
    stability (mirrors the H2→H4 jump from 0.268 to 0.493 in the 15-basin
    benchmark; HBV-96 cascade adds further on top of H4).

Preserves ``N_STATES=4`` and the ``forward_step(state, rain, pet, temp, params)``
signature so ``CoupledHydroModel`` (``coupled_model.py``) can swap in this
class as a drop-in replacement without touching encoder/decoder/normalization.

States (4): ``S_snow``, ``S_soil``, ``S_uz``, ``S_lz``
Parameters (11): ``t0, k_snow, Smax, Ce, beta, K0, K1, UZL, PERC, K2, lag_time``
"""
from typing import Dict, Optional, Tuple

import torch
import torch.nn as nn
import torch.nn.functional as F


PARAM_NAMES = [
    "t0", "k_snow",
    "Smax", "Ce", "beta",
    "K0", "K1", "UZL", "PERC",
    "K2",
    "lag_time",
]
N_PARAMS = len(PARAM_NAMES)

STATE_NAMES = ["S_snow", "S_soil", "S_uz", "S_lz"]
N_STATES = len(STATE_NAMES)

PARAM_BOUNDS = {
    "t0":       (-3.0,   3.0),     # snow threshold temperature [°C]
    "k_snow":   ( 0.5,   8.0),     # degree-day factor [mm/°C/d]
    "Smax":     (50.0, 700.0),     # soil field capacity [mm]
    "Ce":       ( 0.3,   2.0),     # ET coefficient [-]; HBV-light standard range (now that
                                   # data_loading.py uses Oudin PET ≈ correct magnitude;
                                   # the earlier (0.3, 20.0) hack is no longer needed).
    "beta":     ( 1.0,   6.0),     # soil recharge nonlinearity [-]
    "K0":       ( 0.05,  0.99),    # UZ fast outlet rate above UZL [1/d]
    "K1":       ( 0.01,  0.5),     # UZ always-on outlet rate [1/d]
    "UZL":      ( 0.0,  60.0),     # UZ threshold for fast outlet [mm]
    "PERC":     ( 0.0,   6.0),     # UZ→LZ percolation rate [mm/d]
    "K2":       ( 0.0005, 0.15),   # LZ slow outlet rate [1/d]
    "lag_time": ( 1.0,  10.0),     # triangular routing lag [d]
}


class DifferentiableHBV96P1(nn.Module):
    """Differentiable HBV with double-outlet UZ + cascade routing.

    API-compatible with ``DifferentiableHBV`` (same ``N_STATES=4``,
    same ``forward_step / forward`` signature) so it drops into
    ``CoupledHydroModel`` if the param dict supplies the new
    ``PARAM_NAMES``.

    Parameters
    ----------
    n_substep : int
        Number of explicit-Euler sub-steps per daily time step. ``4`` is
        the standard HBV-light default and matches the H4 stability point.
    eps : float
        Small constant for numerical stability in power-law computations.
    """

    def __init__(self, n_substep: int = 4, eps: float = 1e-8):
        super().__init__()
        self.n_substep = n_substep
        self.eps = eps
        self.N_PARAMS = N_PARAMS
        self.N_STATES = N_STATES

    # ------------------------------------------------------------------
    # Single-step interface (for HBV ↔ LSTM coupling)
    # ------------------------------------------------------------------

    def forward_step(
        self,
        state: torch.Tensor,
        rain: torch.Tensor,
        pet: torch.Tensor,
        temp: torch.Tensor,
        params: Dict[str, torch.Tensor],
    ) -> Tuple[torch.Tensor, torch.Tensor]:
        """Run one daily timestep of HBV-96 (P1), internally using ``n_substep`` sub-steps.

        Args:
            state:  [B, 4] — (S_snow, S_soil, S_uz, S_lz)
            rain:   [B, 1] — precipitation [mm/d]
            pet:    [B, 1] — potential ET [mm/d]
            temp:   [B, 1] — mean temperature [°C]
            params: dict of [B, 1] tensors for each of the 11 parameters

        Returns:
            state_next: [B, 4] — updated states
            q_raw:      [B, 1] — instantaneous total discharge (before lag),
                                  summed over sub-steps
        """
        S_snow = state[:, 0:1]
        S_soil = state[:, 1:2]
        S_uz   = state[:, 2:3]
        S_lz   = state[:, 3:4]

        p_t0     = params["t0"]
        p_ksnow  = params["k_snow"]
        p_Smax   = params["Smax"]
        p_Ce     = params["Ce"]
        p_beta   = params["beta"]
        p_K0     = params["K0"]
        p_K1     = params["K1"]
        p_UZL    = params["UZL"]
        p_PERC   = params["PERC"]
        p_K2     = params["K2"]

        n_sub = self.n_substep
        dt = 1.0 / n_sub
        P_sub   = rain * dt
        PET_sub = pet * dt

        q_total = torch.zeros_like(S_snow)

        for _ in range(n_sub):
            # --- Snow module (simple PDD, single state — P1 keeps current snow) ---
            is_snow  = (temp < p_t0).float()
            snowfall = P_sub * is_snow
            rainfall = P_sub * (1.0 - is_snow)
            S_snow   = S_snow + snowfall
            melt_potential = p_ksnow * torch.clamp(temp - p_t0, min=0.0) * dt
            melt    = torch.minimum(melt_potential, S_snow)
            S_snow  = S_snow - melt
            P_eff   = rainfall + melt

            # --- Soil moisture (HBV-light smooth ET + recharge curve) ---
            s_ratio = torch.clamp(S_soil / (p_Smax + self.eps), min=0.0, max=1.0)
            recharge = P_eff * torch.pow(s_ratio + self.eps, p_beta)
            aet      = p_Ce * PET_sub * torch.clamp(s_ratio, max=1.0)
            S_soil   = S_soil + P_eff - recharge - aet
            S_soil   = torch.clamp(S_soil, min=0.0)
            S_soil   = torch.minimum(S_soil, p_Smax)

            # --- UZ: double-outlet (K0 above UZL + K1 always-on) + PERC to LZ ---
            excess        = torch.clamp(S_uz - p_UZL, min=0.0)
            q_K0_pot      = p_K0   * excess * dt
            q_K1_pot      = p_K1   * S_uz   * dt
            q_PERC_pot    = p_PERC * dt
            total_pot     = q_K0_pot + q_K1_pot + q_PERC_pot
            avail_uz      = torch.clamp(S_uz + recharge, min=0.0)
            scale         = torch.where(
                total_pot > avail_uz,
                avail_uz / (total_pot + self.eps),
                torch.ones_like(avail_uz),
            )
            scale         = torch.clamp(scale, max=1.0)
            q_K0   = q_K0_pot   * scale
            q_K1   = q_K1_pot   * scale
            q_PERC = q_PERC_pot * scale
            S_uz   = S_uz + recharge - q_K0 - q_K1 - q_PERC
            S_uz   = torch.clamp(S_uz, min=0.0)

            # --- LZ: linear slow outflow, fed only by PERC (cascade) ---
            q_K2_pot = p_K2 * S_lz * dt
            avail_lz = torch.clamp(S_lz + q_PERC, min=0.0)
            q_K2     = torch.minimum(q_K2_pot, avail_lz)
            S_lz     = S_lz + q_PERC - q_K2
            S_lz     = torch.clamp(S_lz, min=0.0)

            q_total  = q_total + q_K0 + q_K1 + q_K2

        state_next = torch.cat([S_snow, S_soil, S_uz, S_lz], dim=-1)
        return state_next, q_total

    # ------------------------------------------------------------------
    # Full-sequence interface
    # ------------------------------------------------------------------

    def forward(
        self,
        forcing: torch.Tensor,
        params: Dict[str, torch.Tensor],
        state_init: Optional[torch.Tensor] = None,
    ) -> Tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
        """Run HBV-96 (P1) over a full time series.

        Args:
            forcing:    [B, T, 3] — (rain, pet, temp) per daily timestep
            params:     dict of [B, 1] tensors (held constant in time)
            state_init: [B, 4] or None — initial states

        Returns:
            q_sim:      [B, T, 1] — simulated discharge after triangular lag
            q_raw:      [B, T, 1] — discharge before lag
            states_all: [B, T, 4] — state trajectories
        """
        B, T, _ = forcing.shape
        device = forcing.device

        if state_init is None:
            Smax = params["Smax"]
            state = torch.cat([
                torch.zeros(B, 1, device=device),         # S_snow
                Smax * 0.3,                                # S_soil ~ 30% of capacity
                torch.full((B, 1), 5.0, device=device),    # S_uz
                torch.full((B, 1), 10.0, device=device),   # S_lz
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

        q_raw = torch.stack(q_raw_list, dim=1)
        states_all = torch.stack(states_list, dim=1)

        lag_time = params["lag_time"]
        q_sim = self._triangular_lag_batch(q_raw, lag_time)
        return q_sim, q_raw, states_all

    def _triangular_lag_batch(self, q_raw: torch.Tensor, lag_time: torch.Tensor) -> torch.Tensor:
        """Half-triangular lag routing per basin (matches DifferentiableHBV)."""
        B, T, _ = q_raw.shape
        q_out = torch.zeros_like(q_raw)
        for b in range(B):
            lt = lag_time[b, 0].item()
            n = max(int(torch.ceil(torch.tensor(lt)).item()), 1)
            weights = torch.arange(1, n + 1, dtype=torch.float32, device=q_raw.device)
            weights = weights / weights.sum()
            q_1d = q_raw[b, :, 0].unsqueeze(0).unsqueeze(0)
            kernel = weights.flip(0).unsqueeze(0).unsqueeze(0)
            pad = n - 1
            q_conv = F.conv1d(q_1d, kernel, padding=pad)[:, :, :T]
            q_out[b, :, 0] = q_conv.squeeze()
        return q_out

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    @staticmethod
    def constrain_params(raw: torch.Tensor) -> Dict[str, torch.Tensor]:
        """Map unconstrained [B, N_PARAMS] to physically-bounded parameter dict.

        Uses sigmoid scaling to map (-inf, inf) → (lo, hi) for each parameter.
        """
        params = {}
        for i, name in enumerate(PARAM_NAMES):
            lo, hi = PARAM_BOUNDS[name]
            params[name] = torch.sigmoid(raw[:, i:i+1]) * (hi - lo) + lo
        return params

    @staticmethod
    def dict_from_values(values: Dict[str, float], batch_size: int = 1,
                         device: Optional[torch.device] = None) -> Dict[str, torch.Tensor]:
        """Convert scalar param dict to batched tensor dict."""
        if device is None:
            device = torch.device("cpu")
        return {k: torch.full((batch_size, 1), v, dtype=torch.float32, device=device)
                for k, v in values.items()}
