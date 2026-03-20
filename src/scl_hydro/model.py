"""SCL-LSTM model components.

This module contains neural network components for the State Continuity Loss
LSTM framework:

- ObsEncoder: encodes observation context (including Q_obs) into initial LSTM
  hidden/cell states (h_0, c_0).
- SCLCudaLSTM: LSTM model with ObsEncoder for initial state injection.
"""
from typing import Dict, Optional, Tuple

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


class SCLCudaLSTM(nn.Module):
    """LSTM model with observation encoder for initial state injection.

    Mirrors CudaLSTM architecture (embedding → LSTM → dropout → head) but:
    1. Accepts initial states (h_0, c_0) from ObsEncoder instead of zeros.
    2. Uses raw tensor inputs rather than NH data dicts for flexibility.

    Parameters
    ----------
    n_main_features : int
        Number of features in predict_data (forcing inputs).
    n_enc_features : int
        Number of features in context_data (forcing + Q_obs for encoder).
    hidden_size : int
        Hidden size of the main prediction LSTM.
    enc_hidden_size : int
        Hidden size of the encoder LSTM.
    n_targets : int
        Number of output targets (prediction head output size).
    output_dropout : float, optional
        Dropout probability applied to LSTM output before linear head.
        Default is 0.0.
    encoder_dropout : float, optional
        Dropout probability applied inside ObsEncoder.
        Default is 0.0.
    """

    def __init__(self, n_main_features: int, n_enc_features: int, hidden_size: int,
                 enc_hidden_size: int, n_targets: int, output_dropout: float = 0.0,
                 encoder_dropout: float = 0.0):
        super().__init__()
        self.encoder = ObsEncoder(
            input_size=n_enc_features,
            enc_hidden_size=enc_hidden_size,
            main_hidden_size=hidden_size,
            dropout=encoder_dropout,
        )
        self.lstm = nn.LSTM(input_size=n_main_features, hidden_size=hidden_size, batch_first=True)
        self.dropout = nn.Dropout(p=output_dropout)
        self.head = nn.Linear(hidden_size, n_targets)

    def forward(self, predict_data: torch.Tensor,
                context_data: Optional[torch.Tensor] = None) -> Dict[str, torch.Tensor]:
        """Forward pass with optional encoder-based initialization.

        Parameters
        ----------
        predict_data : torch.Tensor
            Shape [batch, seg_len, n_main_features] — forcing inputs.
        context_data : torch.Tensor, optional
            Shape [batch, context_len, n_enc_features] — encoder context.
            If None, LSTM starts from zero initial states.

        Returns
        -------
        dict with keys:
            'y_hat' : [batch, seg_len, n_targets]
            'lstm_output' : [batch, seg_len, hidden_size] — raw LSTM outputs used by SCL trainer.
            'h_n' : [batch, 1, hidden_size] — final hidden state (batch-first).
            'c_n' : [batch, 1, hidden_size] — final cell state (batch-first).
        """
        if context_data is not None:
            h0, c0 = self.encoder(context_data)
            lstm_out, (h_n, c_n) = self.lstm(predict_data, (h0, c0))
        else:
            lstm_out, (h_n, c_n) = self.lstm(predict_data)

        y_hat = self.head(self.dropout(lstm_out))

        return {
            "y_hat": y_hat,
            "lstm_output": lstm_out,
            "h_n": h_n.transpose(0, 1),
            "c_n": c_n.transpose(0, 1),
        }
