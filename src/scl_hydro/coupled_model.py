"""CoupledHydroModel: True alternating HBV ↔ LSTM with gated encoder/decoder bridge.

Even steps (HBV):
  HBV(state, forcing) → new_state, Q
  GatedEncoder updates h, c using [state, forcing, q] (preserves LSTM memory)

Odd steps (LSTM):
  LSTM(forcing, (h, c)) → h', c'
  Decoder(h') → new_state, Q (bridge back to physical space)

LSTM does NOT run on HBV steps. HBV does NOT run on LSTM steps.
GatedEncoder/Decoder is the information bridge between the two models.
"""
from typing import Dict, Optional, Tuple

import torch
import torch.nn as nn

from scl_hydro.hbv_torch import DifferentiableHBV, PARAM_NAMES, N_PARAMS, N_STATES


class GatedStateEncoder(nn.Module):
    """GRU-like gated update of LSTM hidden state from physical state + forcing.

    Instead of replacing h/c from scratch (losing all LSTM memory),
    uses a learned gate to BLEND new physical info with existing memory.

    Input: [state(4), forcing(n_forcing), q(1)] → update h and c via gating.
    """

    def __init__(self, n_input: int, hidden_size: int):
        super().__init__()
        self.hidden_size = hidden_size
        # Gate: how much to update (sigmoid → [0,1])
        self.gate_h = nn.Linear(n_input + hidden_size, hidden_size)
        self.gate_c = nn.Linear(n_input + hidden_size, hidden_size)
        # New candidate values
        self.cand_h = nn.Linear(n_input + hidden_size, hidden_size)
        self.cand_c = nn.Linear(n_input + hidden_size, hidden_size)

    def forward(self, info: torch.Tensor,
                h: torch.Tensor, c: torch.Tensor) -> Tuple[torch.Tensor, torch.Tensor]:
        """Update h, c using gated fusion with new physical info.

        Args:
            info: [B, n_input] — normalized [state, forcing, q]
            h: [1, B, hidden] — current LSTM h
            c: [1, B, hidden] — current LSTM c

        Returns:
            h_new: [1, B, hidden], c_new: [1, B, hidden]
        """
        h_sq = h.squeeze(0)  # [B, hidden]
        c_sq = c.squeeze(0)

        # Concat info with current hidden for gate computation
        cat_h = torch.cat([info, h_sq], dim=-1)  # [B, n_input + hidden]
        cat_c = torch.cat([info, c_sq], dim=-1)

        # Gate: 0 = keep old, 1 = use new
        z_h = torch.sigmoid(self.gate_h(cat_h))
        z_c = torch.sigmoid(self.gate_c(cat_c))

        # New candidate
        h_cand = torch.tanh(self.cand_h(cat_h))
        c_cand = torch.tanh(self.cand_c(cat_c))

        # Gated update
        h_new = z_h * h_cand + (1 - z_h) * h_sq
        c_new = z_c * c_cand + (1 - z_c) * c_sq

        return h_new.unsqueeze(0), c_new.unsqueeze(0)


class StateDecoder(nn.Module):
    """Decode LSTM hidden state → physical state [4] + Q [1].

    Uses mean + softplus(raw) * std so initial output ≈ mean (physically reasonable).
    """

    def __init__(self, hidden_size: int, n_state: int,
                 state_mean: torch.Tensor, state_std: torch.Tensor,
                 q_mean: float = 1.5, q_std: float = 2.5):
        super().__init__()
        self.state_head = nn.Linear(hidden_size, n_state)
        self.q_head = nn.Linear(hidden_size, 1)
        self.register_buffer("state_mean", state_mean)
        self.register_buffer("state_std", state_std)
        self.register_buffer("q_mean", torch.tensor(q_mean))
        self.register_buffer("q_std", torch.tensor(q_std))

    def forward(self, lstm_out: torch.Tensor) -> Tuple[torch.Tensor, torch.Tensor]:
        raw_state = self.state_head(lstm_out)
        state = self.state_mean + nn.functional.softplus(raw_state) * self.state_std
        state = torch.clamp(state, min=0.0)
        raw_q = self.q_head(lstm_out)
        q = nn.functional.softplus(raw_q) * self.q_std
        return state, q


class CoupledHydroModel(nn.Module):
    """True alternating HBV ↔ LSTM with gated encoder bridge.

    Parameters
    ----------
    n_forcing : int
        Number of meteorological forcing features.
    hidden_size : int
        LSTM hidden state dimension.
    hbv_params : dict
        Fixed HBV parameters (from calibration).
    forcing_mean, forcing_std : torch.Tensor, optional
        z-score normalization for forcing input.
    state_mean, state_std : torch.Tensor, optional
        Mean/std of physical states for encoder normalization and decoder output.
    q_mean, q_std : float
        Mean/std of Q for decoder output scaling.
    stride : int
        Alternation stride. stride=2 means HBV,LSTM,HBV,LSTM,...
    """

    def __init__(self, n_forcing: int, hidden_size: int,
                 hbv_params: Dict[str, float],
                 forcing_mean: Optional[torch.Tensor] = None,
                 forcing_std: Optional[torch.Tensor] = None,
                 state_mean: Optional[torch.Tensor] = None,
                 state_std: Optional[torch.Tensor] = None,
                 q_mean: float = 1.5, q_std: float = 2.5,
                 stride: int = 2):
        super().__init__()
        self.n_forcing = n_forcing
        self.hidden_size = hidden_size
        self.stride = stride

        # Fixed HBV parameters
        for name in PARAM_NAMES:
            self.register_buffer(f"hbv_{name}",
                                 torch.tensor(hbv_params[name], dtype=torch.float32))

        # Normalization
        if forcing_mean is not None:
            self.register_buffer("forcing_mean", forcing_mean)
            self.register_buffer("forcing_std", forcing_std)
        else:
            self.register_buffer("forcing_mean", None)
            self.register_buffer("forcing_std", None)

        if state_mean is None:
            state_mean = torch.tensor([64.0, 30.0, 3.0, 12.0])
        if state_std is None:
            state_std = torch.tensor([98.0, 14.5, 3.0, 13.3])
        self.register_buffer("state_mean", state_mean)
        self.register_buffer("state_std", state_std)
        self.register_buffer("q_scale", torch.tensor(max(q_std, 1.0)))

        # Gated encoder: [state_norm(4) + forcing_norm(n_forcing) + q_norm(1)] → update h, c
        encoder_input_size = N_STATES + n_forcing + 1
        self.encoder = GatedStateEncoder(encoder_input_size, hidden_size)

        # LSTM: processes normalized forcing on LSTM steps
        self.lstm = nn.LSTM(input_size=n_forcing, hidden_size=hidden_size, batch_first=True)

        # Decoder: LSTM hidden → physical state + Q
        self.decoder = StateDecoder(hidden_size, N_STATES, state_mean, state_std, q_mean, q_std)

        # HBV
        self.hbv = DifferentiableHBV()

    def _get_hbv_params(self, B: int, device: torch.device) -> Dict[str, torch.Tensor]:
        return {name: getattr(self, f"hbv_{name}").expand(B, 1) for name in PARAM_NAMES}

    def _normalize_forcing(self, forcing_t: torch.Tensor) -> torch.Tensor:
        if self.forcing_mean is not None:
            return (forcing_t - self.forcing_mean) / (self.forcing_std + 1e-8)
        return forcing_t

    def forward(
        self,
        forcing: torch.Tensor,
        hbv_forcing_idx: Tuple[int, int, int] = (0, 1, 2),
        state_init: Optional[torch.Tensor] = None,
    ) -> Dict[str, torch.Tensor]:
        B, T, _ = forcing.shape
        device = forcing.device
        i_rain, i_pet, i_temp = hbv_forcing_idx

        params = self._get_hbv_params(B, device)

        # Initialize physical state
        if state_init is not None:
            state = state_init
        else:
            Smax = params["Smax"]
            state = torch.zeros(B, N_STATES, device=device)
            state[:, 1] = (Smax[:, 0] * 0.3).detach()
            state[:, 2] = 5.0
            state[:, 3] = 5.0

        # LSTM initial h/c = zeros
        h = torch.zeros(1, B, self.hidden_size, device=device)
        c = torch.zeros(1, B, self.hidden_size, device=device)

        q_list = []
        states_list = []
        step_types = []

        for t in range(T):
            is_hbv_step = (t % self.stride == 0)

            if is_hbv_step:
                # === HBV step ===
                rain = forcing[:, t, i_rain:i_rain + 1]
                pet  = forcing[:, t, i_pet:i_pet + 1]
                temp = forcing[:, t, i_temp:i_temp + 1]
                state, q = self.hbv.forward_step(state, rain, pet, temp, params)

                # Gated update of h, c (preserves memory + adds new info)
                state_norm = (state - self.state_mean) / (self.state_std + 1e-8)
                f_norm = self._normalize_forcing(forcing[:, t, :])
                q_norm = q / (self.q_scale + 1e-8)
                encoder_input = torch.cat([state_norm, f_norm, q_norm], dim=-1)
                h, c = self.encoder(encoder_input, h, c)

                step_types.append(0)

            else:
                # === LSTM step ===
                f_norm = self._normalize_forcing(forcing[:, t, :])
                f_norm = f_norm.unsqueeze(1)
                lstm_out, (h, c) = self.lstm(f_norm, (h, c))

                # Decode → physical state + Q
                state, q = self.decoder(lstm_out.squeeze(1))

                step_types.append(1)

            q_list.append(q)
            states_list.append(state)

        return {
            "y_hat": torch.stack(q_list, dim=1),
            "phys_states": torch.stack(states_list, dim=1),
            "step_type": torch.tensor(step_types, dtype=torch.long),
        }
