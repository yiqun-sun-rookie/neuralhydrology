from typing import Dict

import torch
import torch.nn as nn

from neuralhydrology.modelzoo.inputlayer import InputLayer
from neuralhydrology.modelzoo.head import get_head
from neuralhydrology.modelzoo.basemodel import BaseModel
from neuralhydrology.utils.config import Config

# Try to import Mamba implementations with fallback
MAMBA_BACKEND = None

# Priority 1: Try official mamba_ssm (fastest, but requires CUDA compilation)
try:
    from mamba_ssm import Mamba as Mamba_SSM
    MAMBA_BACKEND = "mamba_ssm"
except (ModuleNotFoundError, ImportError):
    Mamba_SSM = None

# Priority 2: Try Hugging Face transformers (slower but universal, Windows-friendly)
try:
    from transformers import MambaConfig, MambaModel as HF_MambaModel
    if MAMBA_BACKEND is None:
        MAMBA_BACKEND = "transformers"
except (ModuleNotFoundError, ImportError):
    HF_MambaModel = None
    MambaConfig = None


class Mamba(BaseModel):
    """Mamba State Space Model for hydrological time series modeling.

    This class implements the Mamba SSM architecture for rainfall-runoff prediction.
    It supports two backends:
    
    1. **mamba_ssm** (official): Fastest, requires CUDA compilation. 
       Install: `pip install mamba_ssm causal-conv1d>=1.1.0`
       
    2. **transformers** (Hugging Face): Universal, Windows-friendly, no compilation needed.
       Install: `pip install transformers`
    
    The backend is automatically selected based on availability (mamba_ssm > transformers).
    
    Mamba is particularly well-suited for hourly-scale hydrological modeling due to:
    - Linear complexity O(N) for long sequences (vs O(N²) for Transformers)
    - Efficient handling of very long time series (e.g., 8760 hours = 1 year)
    - State-space formulation that naturally captures temporal dynamics

    Parameters
    ----------
    cfg : Config
        The run configuration. Mamba-specific parameters:
        - hidden_size: Model dimension (d_model)
        - mamba_d_state: SSM state expansion factor (default: 16)
        - mamba_d_conv: Local convolution width (default: 4)
        - mamba_expand: Block expansion factor (default: 2)
        - mamba_n_layers: Number of Mamba layers (default: 2, HF backend only)
    """
    # specify submodules of the model that can later be used for finetuning
    module_parts = ['embedding_net', 'transition_layer', 'mamba', 'head']

    def __init__(self, cfg: Config):
        super(Mamba, self).__init__(cfg=cfg)

        self.embedding_net = InputLayer(cfg)

        # Transition layer: map from embedding dimension to hidden size
        self.transition_layer = nn.Linear(self.embedding_net.output_size, cfg.hidden_size)

        # Get Mamba-specific hyperparameters with defaults
        d_state = getattr(cfg, 'mamba_d_state', 16)
        d_conv = getattr(cfg, 'mamba_d_conv', 4)
        expand = getattr(cfg, 'mamba_expand', 2)
        n_layers = getattr(cfg, 'mamba_n_layers', 2)

        self.backend = MAMBA_BACKEND

        if self.backend == "mamba_ssm":
            # Use official mamba_ssm library (fastest)
            self.mamba = Mamba_SSM(
                d_model=cfg.hidden_size,
                d_state=d_state,
                d_conv=d_conv,
                expand=expand,
            )
        elif self.backend == "transformers":
            # Use Hugging Face transformers (universal, Windows-friendly)
            mamba_config = MambaConfig(
                hidden_size=cfg.hidden_size,
                state_size=d_state,
                conv_kernel=d_conv,
                expand=expand,
                num_hidden_layers=n_layers,
                # Disable vocab embedding since we use continuous inputs
                vocab_size=1,  # Dummy, not used
            )
            self.mamba = HF_MambaModel(mamba_config)
        else:
            raise ModuleNotFoundError(
                "No Mamba backend available. Please install one of:\n"
                "  1. Hugging Face (recommended for Windows): pip install transformers\n"
                "  2. Official mamba_ssm (fastest, Linux/CUDA): pip install mamba_ssm causal-conv1d>=1.1.0"
            )

        self.dropout = nn.Dropout(p=cfg.output_dropout)
        self.head = get_head(cfg=cfg, n_in=cfg.hidden_size, n_out=self.output_size)

        print(f"[Mamba] Initialized with backend: {self.backend}")

    def forward(self, data: dict[str, torch.Tensor | dict[str, torch.Tensor]]) -> Dict[str, torch.Tensor]:
        """Perform a forward pass on the Mamba model.

        Parameters
        ----------
        data : dict[str, torch.Tensor | dict[str, torch.Tensor]]
            Dictionary containing input features as key-value pairs.

        Returns
        -------
        Dict[str, torch.Tensor]
            Model outputs and intermediate states as a dictionary.
                - `y_hat`: model predictions of shape [batch size, sequence length, number of target variables].
        """
        # Pass dynamic and static inputs through embedding layers, then concatenate
        x_d = self.embedding_net(data)  # [seq_len, batch_size, embedding_dim]

        # Reshape to [batch_size, seq_len, embedding_dim] for transition layer
        x_d = x_d.transpose(0, 1)
        
        # Project to hidden size
        x_d = self.transition_layer(x_d)  # [batch_size, seq_len, hidden_size]

        if self.backend == "mamba_ssm":
            # mamba_ssm expects [batch, seq, hidden]
            mamba_output = self.mamba(x_d)  # [batch, seq, hidden]
        else:
            # Hugging Face expects [batch, seq, hidden], returns MambaOutput
            mamba_out = self.mamba(inputs_embeds=x_d)
            mamba_output = mamba_out.last_hidden_state  # [batch, seq, hidden]

        # Apply dropout and head
        pred = {'y_hat': mamba_output}
        pred.update(self.head(self.dropout(mamba_output)))
        
        return pred
