"""Differentiable HBV-light in PyTorch.

Port of the standard HBV-light algorithm from mhpi/hydroDL2
(https://github.com/mhpi/hydroDL2, src/hydrodl2/models/hbv/hbv.py::_PBM)
into our standalone PyTorch framework. Stays compatible with
``calibrate_*`` patterns already used for ``DifferentiableHBV96P1`` so
sanity / 531-runner can swap models with minimal change.

States (5): SNOWPACK, MELTWATER, SM, SUZ, SLZ
Parameters (12 phy + 1 lag = 13):
    parTT, parCFMAX, parCFR, parCWH         (snow 4)
    parFC, parBETA, parLP                   (soil 3)
    parK0, parK1, parUZL, parPERC           (UZ 4)
    parK2                                   (LZ 1)
    lag_time                                 (routing 1, our simple half-triangular lag)

References
----------
Feng, D., Liu, J., Lawson, K., & Shen, C. (2022). Differentiable, learnable,
regionalized process-based models with multiphysical outputs can approach
state-of-the-art hydrologic prediction accuracy. Water Resources Research,
58, e2022WR032404. https://doi.org/10.1029/2022WR032404

Seibert, J. (2005). HBV-light Version 2 User's Manual. Stockholm University.

Beck, H. E. et al. (2020). Global Fully Distributed Parameter Regionalization
Based on Observed Streamflow From 4,229 Headwater Catchments. JGR Atmospheres.
"""
from typing import Dict, Optional, Tuple

import torch
import torch.nn as nn
import torch.nn.functional as F


PARAM_NAMES = [
    "parTT", "parCFMAX", "parCFR", "parCWH",
    "parFC", "parBETA", "parLP",
    "parK0", "parK1", "parUZL", "parPERC",
    "parK2",
    "lag_time",
]
N_PARAMS = len(PARAM_NAMES)

STATE_NAMES = ["SNOWPACK", "MELTWATER", "SM", "SUZ", "SLZ"]
N_STATES = len(STATE_NAMES)

# Bounds match hydroDL2 hbv.py defaults verbatim (Feng et al. 2022)
PARAM_BOUNDS = {
    # Snow (HBV-light standard)
    "parTT":    (-2.5,  2.5),   # snow/rain threshold temp [°C]
    "parCFMAX": ( 0.5, 10.0),   # degree-day melt factor [mm/°C/d]
    "parCFR":   ( 0.0,  0.1),   # refreeze coefficient [-]
    "parCWH":   ( 0.0,  0.2),   # water holding capacity in snowpack [-]
    # Soil
    "parFC":    (50.0, 1000.0), # field capacity [mm]
    "parBETA":  ( 1.0,  6.0),   # soil recharge curve exponent [-]
    "parLP":    ( 0.2,  1.0),   # soil moisture threshold for full ET [-]
    # Upper zone (with double outlet)
    "parK0":    (0.05,  0.9),   # UZ above-threshold rate [1/d]
    "parK1":    (0.01,  0.5),   # UZ baseline rate [1/d]
    "parUZL":   ( 0.0,  100.0), # UZ threshold [mm]
    "parPERC":  ( 0.0,  10.0),  # UZ→LZ percolation rate [mm/d]
    # Lower zone
    "parK2":    (0.001, 0.2),   # LZ baseflow rate [1/d]
    # Routing (our simple triangular lag, hydroDL2 uses Gamma UH; first iteration
    # we keep things simple)
    "lag_time": ( 1.0,  10.0),  # triangular routing lag [d]
}


class DifferentiableHBVLite(nn.Module):
    """Differentiable HBV-light, single-component, fixed parameters per basin.

    Algorithm is bit-for-bit (modulo Gamma-UH-vs-triangular routing) the
    hydroDL2 reference implementation. Daily explicit Euler — each reservoir
    is clamped against under/over flow so dt=1 is numerically safe.

    State naming matches HBV-light tradition (SNOWPACK = frozen,
    MELTWATER = liquid water held in pack via CWH, SM = soil moisture,
    SUZ = upper zone groundwater, SLZ = lower zone groundwater).
    """

    def __init__(self, eps: float = 1e-5):
        super().__init__()
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
        """One daily timestep of HBV-light.

        Args:
            state:  [B, 5] — (SNOWPACK, MELTWATER, SM, SUZ, SLZ)
            rain:   [B, 1] — total precipitation [mm/d]
            pet:    [B, 1] — potential ET [mm/d]
            temp:   [B, 1] — mean temperature [°C]
            params: dict of [B, 1] tensors for each of the 13 parameters

        Returns:
            state_next: [B, 5]
            q_raw:      [B, 1] — total discharge before lag
        """
        SNOWPACK  = state[:, 0:1]
        MELTWATER = state[:, 1:2]
        SM        = state[:, 2:3]
        SUZ       = state[:, 3:4]
        SLZ       = state[:, 4:5]

        TT     = params["parTT"]
        CFMAX  = params["parCFMAX"]
        CFR    = params["parCFR"]
        CWH    = params["parCWH"]
        FC     = params["parFC"]
        BETA   = params["parBETA"]
        LP     = params["parLP"]
        K0     = params["parK0"]
        K1     = params["parK1"]
        UZL    = params["parUZL"]
        PERC   = params["parPERC"]
        K2     = params["parK2"]

        # --- Snow ---
        is_snow  = (temp < TT).float()
        SNOW     = rain * is_snow
        RAIN     = rain * (1.0 - is_snow)

        SNOWPACK = SNOWPACK + SNOW
        melt = CFMAX * (temp - TT)
        melt = torch.clamp(melt, min=0.0)
        melt = torch.minimum(melt, SNOWPACK)
        MELTWATER = MELTWATER + melt
        SNOWPACK  = SNOWPACK - melt

        refreezing = CFR * CFMAX * (TT - temp)
        refreezing = torch.clamp(refreezing, min=0.0)
        refreezing = torch.minimum(refreezing, MELTWATER)
        SNOWPACK   = SNOWPACK + refreezing
        MELTWATER  = MELTWATER - refreezing

        tosoil    = MELTWATER - CWH * SNOWPACK
        tosoil    = torch.clamp(tosoil, min=0.0)
        MELTWATER = MELTWATER - tosoil

        # --- Soil + ET ---
        soil_wetness = torch.pow(SM / (FC + self.eps), BETA)
        soil_wetness = torch.clamp(soil_wetness, min=0.0, max=1.0)
        recharge     = (RAIN + tosoil) * soil_wetness
        SM           = SM + RAIN + tosoil - recharge

        excess = torch.clamp(SM - FC, min=0.0)
        SM     = SM - excess

        evapfactor = SM / (LP * FC + self.eps)
        evapfactor = torch.clamp(evapfactor, min=0.0, max=1.0)
        ETact      = pet * evapfactor
        ETact      = torch.minimum(SM, ETact)
        SM         = torch.clamp(SM - ETact, min=self.eps)

        # --- Groundwater ---
        SUZ = SUZ + recharge + excess
        PERC_flux = torch.minimum(SUZ, PERC)  # capped at available
        SUZ = SUZ - PERC_flux
        Q0  = K0 * torch.clamp(SUZ - UZL, min=0.0)
        SUZ = SUZ - Q0
        Q1  = K1 * SUZ
        SUZ = SUZ - Q1
        SLZ = SLZ + PERC_flux
        Q2  = K2 * SLZ
        SLZ = SLZ - Q2

        q_raw = Q0 + Q1 + Q2

        state_next = torch.cat([SNOWPACK, MELTWATER, SM, SUZ, SLZ], dim=-1)
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
        """Run HBV-light over a full time series.

        Args:
            forcing:    [B, T, 3] — (rain, pet, temp) per daily timestep
            params:     dict of [B, 1] tensors
            state_init: [B, 5] or None

        Returns:
            q_sim:      [B, T, 1] after triangular lag
            q_raw:      [B, T, 1] pre-lag
            states_all: [B, T, 5]
        """
        B, T, _ = forcing.shape
        device  = forcing.device

        if state_init is None:
            FC = params["parFC"]
            state = torch.cat([
                torch.zeros(B, 1, device=device),         # SNOWPACK
                torch.zeros(B, 1, device=device),         # MELTWATER
                FC * 0.3,                                  # SM ~ 30% of FC
                torch.full((B, 1), 5.0, device=device),    # SUZ
                torch.full((B, 1), 10.0, device=device),   # SLZ
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
        """Apply RISING-half triangular routing lag (peak delayed by n-1 days).

        With ``n = ceil(lag_time)`` and weights ``w_k = (k+1)/sum`` for
        ``k = 0..n-1``, the simulated discharge at day ``t`` is::

            q_sim[t] = w_{n-1}*q_raw[t-n+1] + w_{n-2}*q_raw[t-n+2] + ... + w_0*q_raw[t]

        where ``w_{n-1}`` is the LARGEST weight on the OLDEST raw runoff,
        emulating concentration time. Peak at t = n-1.

        NOTE: This DIFFERS from the recession-half triangular UH in the
        NumPy ``hbv_lite_numpy._half_triangular_lag`` implementation (peak
        at t=0). The 9-way ensemble production runs use the NumPy
        recession-half. This PyTorch rising-half implementation is
        currently used only for the lag-bug sensitivity diagnostic
        (``diagnose_lag_bug.py``). See
        ``docs/technical/camels_531_lockdown_report_20260602.md``.
        """
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
        """Map unconstrained [B, N_PARAMS] → physically bounded dict via sigmoid."""
        params = {}
        for i, name in enumerate(PARAM_NAMES):
            lo, hi = PARAM_BOUNDS[name]
            params[name] = torch.sigmoid(raw[:, i:i+1]) * (hi - lo) + lo
        return params

    @staticmethod
    def dict_from_values(values: Dict[str, float], batch_size: int = 1,
                         device: Optional[torch.device] = None) -> Dict[str, torch.Tensor]:
        if device is None:
            device = torch.device("cpu")
        return {k: torch.full((batch_size, 1), v, dtype=torch.float32, device=device)
                for k, v in values.items()}
