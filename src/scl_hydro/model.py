"""SCL-LSTM model components.

This module contains neural network components for the State Continuity Loss
LSTM framework:

- ObsEncoder: encodes observation context (including Q_obs) into initial LSTM
  hidden/cell states (h_0, c_0).
"""
from typing import Tuple

import torch
import torch.nn as nn


class ObsEncoder(nn.Module):
    """Encodes observation context [P, T, Q_obs, ...] into LSTM initial states (h_0, c_0).

    Uses a small LSTM to process the context window, then projects the final hidden/cell
    states to the main model's hidden size via separate linear layers.

    Parameters
    ----------
    input_size : int
        Number of features in the context window (e.g. forcing + Q_obs).
    enc_hidden_size : int
        Hidden size of the encoder LSTM.
    main_hidden_size : int
        Hidden size of the main prediction LSTM (output dimension of projections).
    dropout : float, optional
        Dropout probability applied to encoder final states before projection.
        Default is 0.0 (no dropout).
    """

    def __init__(self, input_size: int, enc_hidden_size: int, main_hidden_size: int,
                 dropout: float = 0.0):
        super().__init__()
        self.lstm = nn.LSTM(input_size=input_size, hidden_size=enc_hidden_size, batch_first=True)
        self.proj_h = nn.Linear(enc_hidden_size, main_hidden_size)
        self.proj_c = nn.Linear(enc_hidden_size, main_hidden_size)
        self.dropout = nn.Dropout(p=dropout)

    def forward(self, x: torch.Tensor) -> Tuple[torch.Tensor, torch.Tensor]:
        """Encode context observations into initial LSTM states.

        Parameters
        ----------
        x : torch.Tensor
            Shape [batch, context_len, input_size] — context window features
            including Q_obs.

        Returns
        -------
        h_0 : torch.Tensor
            Shape [1, batch, main_hidden_size] — initial hidden state for main LSTM.
        c_0 : torch.Tensor
            Shape [1, batch, main_hidden_size] — initial cell state for main LSTM.
        """
        _, (h_n, c_n) = self.lstm(x)
        # h_n, c_n: [1, batch, enc_hidden_size]
        h_0 = self.proj_h(self.dropout(h_n.squeeze(0))).unsqueeze(0)  # [1, batch, main_hidden]
        c_0 = self.proj_c(self.dropout(c_n.squeeze(0))).unsqueeze(0)
        return h_0, c_0
