import logging
from typing import Dict

import torch
import torch.nn as nn

from neuralhydrology.datautils.utils import get_frequency_factor, sort_frequencies
from neuralhydrology.modelzoo.head import get_head
from neuralhydrology.modelzoo.basemodel import BaseModel
from neuralhydrology.modelzoo.inputlayer import InputLayer
from neuralhydrology.utils.config import Config

LOGGER = logging.getLogger(__name__)

# Try to import Mamba implementations with fallback (same logic as mamba.py, kept independent)
_MAMBA_BACKEND = None

try:
    from mamba_ssm import Mamba as Mamba_SSM
    _MAMBA_BACKEND = "mamba_ssm"
except (ModuleNotFoundError, ImportError):
    Mamba_SSM = None

try:
    from transformers import MambaConfig, MambaModel as HF_MambaModel
    if _MAMBA_BACKEND is None:
        _MAMBA_BACKEND = "transformers"
except (ModuleNotFoundError, ImportError):
    HF_MambaModel = None
    MambaConfig = None


class MTSMamba(BaseModel):
    """Multi-Timescale Mamba (MTS-Mamba) with Context Prepend state transfer.

    A multi-timescale version of the Mamba State Space Model for simultaneous prediction at multiple temporal
    resolutions. It mirrors the MTS-LSTM architecture (Gauch et al., 2020) but replaces LSTM blocks with Mamba blocks
    and uses "Context Prepend" instead of (h, c) state transfer.

    Context Prepend mechanism:
    1. Lower-frequency Mamba processes its full input sequence.
    2. The output at the state transfer point is extracted as a context token.
    3. The context token is projected (via FC) to match the next-higher frequency's hidden size.
    4. The projected token is prepended to the higher-frequency input sequence.
    5. The higher-frequency Mamba naturally absorbs the context through its selective scan.
    6. The first timestep (context token position) is discarded from the output.

    Parameters
    ----------
    cfg : Config
        The run configuration. Relevant parameters:

        - ``hidden_size``: int or dict mapping frequency to hidden size.
        - ``use_frequencies``: list of frequency strings (e.g., ``['1D', '1h']``).
        - ``transfer_mtsmamba_states``: str, one of ``'linear'``, ``'identity'``, ``'None'``.
        - ``mamba_d_state``, ``mamba_d_conv``, ``mamba_expand``, ``mamba_n_layers``: Mamba hyperparameters.

    References
    ----------
    .. [#] Gauch, M., Kratzert, F., Klotz, D., Grey, N., Lin, J., and Hochreiter, S.: Rainfall-Runoff Prediction at
        Multiple Timescales with a Single Long Short-Term Memory Network, arXiv, 2020.
    """
    module_parts = ['embedding_net', 'transition_layers', 'mambas', 'transfer_fcs', 'heads']

    def __init__(self, cfg: Config):
        super(MTSMamba, self).__init__(cfg=cfg)

        if len(cfg.use_frequencies) < 2:
            raise ValueError("MTS-Mamba expects more than one input frequency")
        self._frequencies = sort_frequencies(cfg.use_frequencies)
        self._seq_lengths = cfg.seq_length

        # Transfer mode
        self._transfer_mode = cfg.transfer_mtsmamba_states
        valid_modes = [None, "None", "identity", "linear"]
        if self._transfer_mode not in valid_modes:
            raise ValueError(f"MTS-Mamba supports transfer modes {valid_modes}")

        # Per-frequency hidden sizes
        if not isinstance(cfg.hidden_size, dict):
            LOGGER.info("No specific hidden size for frequencies. Same hidden size is used for all.")
            self._hidden_size = {freq: cfg.hidden_size for freq in self._frequencies}
        else:
            self._hidden_size = cfg.hidden_size

        if self._transfer_mode == "identity" \
                and any(s != self._hidden_size[self._frequencies[0]] for s in self._hidden_size.values()):
            raise ValueError("All hidden sizes must be equal when transfer_mtsmamba_states='identity'.")

        # Per-frequency dynamic inputs
        if isinstance(cfg.dynamic_inputs, list):
            if isinstance(cfg.dynamic_inputs[0], list):
                raise ValueError("MTS-Mamba does not support input feature groups.")
            self._dynamic_inputs = {freq: cfg.dynamic_inputs for freq in self._frequencies}
        else:
            self._dynamic_inputs = cfg.dynamic_inputs

        # Mamba backend
        self.backend = _MAMBA_BACKEND
        if self.backend is None:
            raise ModuleNotFoundError(
                "No Mamba backend available. Please install one of:\n"
                "  1. Hugging Face (recommended for Windows): pip install transformers\n"
                "  2. Official mamba_ssm (fastest, Linux/CUDA): pip install mamba_ssm causal-conv1d>=1.1.0")

        # Per-frequency embedding networks
        self.embedding_net = nn.ModuleDict()
        for freq in self._frequencies:
            freq_params = {
                'model': 'mtsmamba',
                'dynamic_inputs': cfg.dynamic_inputs[freq] if isinstance(cfg.dynamic_inputs, dict) else cfg.dynamic_inputs,
                'dynamics_embedding': cfg.dynamics_embedding,
                'static_attributes': cfg.static_attributes,
                'statics_embedding': cfg.statics_embedding,
                'use_basin_id_encoding': cfg.use_basin_id_encoding,
                'number_of_basins': cfg.number_of_basins,
                'head': cfg.head,
                'seq_length': cfg.seq_length[freq] if isinstance(cfg.seq_length, dict) else cfg.seq_length,
            }
            freq_cfg = Config(freq_params)
            self.embedding_net[freq] = InputLayer(freq_cfg, embedding_type='full_model')

        # Mamba hyperparameters
        d_state = getattr(cfg, 'mamba_d_state', 16)
        d_conv = getattr(cfg, 'mamba_d_conv', 4)
        expand = getattr(cfg, 'mamba_expand', 2)
        n_layers = getattr(cfg, 'mamba_n_layers', 2)

        # Per-frequency modules
        self.transition_layers = nn.ModuleDict()
        self.mambas = nn.ModuleDict()
        self.heads = nn.ModuleDict()
        self.transfer_fcs = nn.ModuleDict()
        self.dropout = nn.Dropout(p=cfg.output_dropout)

        for idx, freq in enumerate(self._frequencies):
            hidden = self._hidden_size[freq]

            self.transition_layers[freq] = nn.Linear(self.embedding_net[freq].output_size, hidden)

            if self.backend == "mamba_ssm":
                self.mambas[freq] = Mamba_SSM(d_model=hidden, d_state=d_state, d_conv=d_conv, expand=expand)
            else:
                mamba_config = MambaConfig(hidden_size=hidden, state_size=d_state, conv_kernel=d_conv, expand=expand,
                                           num_hidden_layers=n_layers, vocab_size=1)
                self.mambas[freq] = HF_MambaModel(mamba_config)

            self.heads[freq] = get_head(cfg, n_in=hidden, n_out=self.output_size)

            if idx < len(self._frequencies) - 1:
                next_hidden = self._hidden_size[self._frequencies[idx + 1]]
                if self._transfer_mode == "linear":
                    self.transfer_fcs[freq] = nn.Linear(hidden, next_hidden)
                elif self._transfer_mode == "identity":
                    self.transfer_fcs[freq] = nn.Identity()

        # Frequency factors and slice timesteps (same logic as MTS-LSTM)
        self._frequency_factors = []
        self._slice_timestep = {}
        for idx, freq in enumerate(self._frequencies):
            if idx < len(self._frequencies) - 1:
                frequency_factor = get_frequency_factor(freq, self._frequencies[idx + 1])
                if frequency_factor != int(frequency_factor):
                    raise ValueError('Adjacent frequencies must be multiples of each other.')
                self._frequency_factors.append(int(frequency_factor))
                slice_timestep = int(self._seq_lengths[self._frequencies[idx + 1]] / self._frequency_factors[idx])
                self._slice_timestep[freq] = slice_timestep

        LOGGER.info(f"[MTS-Mamba] backend={self.backend}, frequencies={self._frequencies}, "
                     f"transfer={self._transfer_mode}")

    def _prepare_inputs(self, data: Dict[str, torch.Tensor], freq: str) -> torch.Tensor:
        """Prepare per-frequency inputs through embedding network.

        Parameters
        ----------
        data : Dict[str, torch.Tensor]
            Input data dict with frequency-suffixed keys.
        freq : str
            Frequency string (e.g., '1D', '1h').

        Returns
        -------
        torch.Tensor
            Embedded input of shape ``[seq_len, batch, embedding_dim]``.
        """
        input_data = {
            'x_d': data[f'x_d_{freq}'],
            'x_s': data.get('x_s'),
            'x_one_hot': data.get('x_one_hot'),
        }
        if f'x_s_{freq}' in data:
            input_data['x_s'] = data[f'x_s_{freq}']
        input_data = {k: v for k, v in input_data.items() if v is not None}
        return self.embedding_net[freq](input_data, concatenate_output=True)

    def _run_mamba(self, freq: str, x: torch.Tensor) -> torch.Tensor:
        """Run Mamba block for a given frequency, abstracting backend differences.

        Parameters
        ----------
        freq : str
            Frequency key for selecting the correct Mamba module.
        x : torch.Tensor
            Input tensor of shape ``[batch, seq_len, hidden]``.

        Returns
        -------
        torch.Tensor
            Output tensor of shape ``[batch, seq_len, hidden]``.
        """
        if self.backend == "mamba_ssm":
            return self.mambas[freq](x)
        else:
            return self.mambas[freq](inputs_embeds=x).last_hidden_state

    def forward(self, data: dict[str, torch.Tensor | dict[str, torch.Tensor]]) -> Dict[str, torch.Tensor]:
        """Perform a forward pass on the MTS-Mamba model.

        Parameters
        ----------
        data : dict[str, torch.Tensor | dict[str, torch.Tensor]]
            Input data for the forward pass.

        Returns
        -------
        Dict[str, torch.Tensor]
            Model predictions for each target timescale, keyed by ``{output_key}_{freq}``.
        """
        # Prepare per-frequency inputs: [seq_len, batch, emb_dim]
        x_d = {freq: self._prepare_inputs(data, freq) for freq in self._frequencies}

        # Transition to hidden dim and reshape for Mamba: [batch, seq_len, hidden]
        x_hidden = {}
        for freq in self._frequencies:
            x_hidden[freq] = self.transition_layers[freq](x_d[freq].transpose(0, 1))

        context_token = None
        outputs = {}

        for idx, freq in enumerate(self._frequencies):
            mamba_input = x_hidden[freq]  # [batch, T_freq, hidden_freq]

            # Prepend context token from previous (lower) frequency
            if idx > 0 and context_token is not None:
                mamba_input = torch.cat([context_token, mamba_input], dim=1)  # [batch, T_freq+1, hidden_freq]

            # Run Mamba
            mamba_output = self._run_mamba(freq, mamba_input)  # [batch, T_freq(+1), hidden_freq]

            # Strip context token position from output
            if idx > 0 and context_token is not None:
                mamba_output = mamba_output[:, 1:, :]  # [batch, T_freq, hidden_freq]

            # Extract context for next frequency (at the state transfer point)
            if idx < len(self._frequencies) - 1 and self._transfer_mode not in (None, "None"):
                slice_ts = self._slice_timestep[freq]
                transfer_idx = mamba_output.shape[1] - slice_ts - 1
                raw_context = mamba_output[:, transfer_idx:transfer_idx + 1, :]  # [batch, 1, hidden_freq]
                context_token = self.transfer_fcs[freq](raw_context)  # [batch, 1, hidden_next_freq]
            else:
                context_token = None

            # Output head
            head_out = self.heads[freq](self.dropout(mamba_output))
            outputs.update({f'{key}_{freq}': value for key, value in head_out.items()})

        return outputs
