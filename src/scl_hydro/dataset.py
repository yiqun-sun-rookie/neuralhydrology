from typing import Dict, List, Optional
import numpy as np
import pandas as pd
import torch
from torch.utils.data import Dataset


class SCLDataset(Dataset):
    """Dataset that returns overlapping segment pairs for SCL training.

    Each sample consists of two temporally overlapping segments (seg_k, seg_k+1) from
    the same basin. Both include a context window (for the encoder) and a prediction
    window (for the main model).

    Temporal layout::

        seg_k:   [--context_k--][--------predict_k--------]
        seg_k+1:                       [--context_k+1--][--------predict_k+1--------]
        overlap:                                        |overlap_len|

    The last ``overlap_length`` timesteps of ``predict_k`` are temporally identical to
    the first ``overlap_length`` timesteps of ``predict_k+1``.  The State Continuity
    Loss penalises the difference between the hidden states on these shared timesteps.
    """

    def __init__(
        self,
        data: Dict[str, pd.DataFrame],
        seg_length: int,
        context_length: int,
        overlap_length: int,
        main_features: List[str],
        enc_features: List[str],
        target: str,
        scaler: Optional[dict] = None,
    ):
        super().__init__()
        self.seg_length = seg_length
        self.context_length = context_length
        self.overlap_length = overlap_length
        self.main_features = main_features
        self.enc_features = enc_features
        self.target = target

        # Number of non-overlapping timesteps between the start of seg_k and seg_k+1
        self._step = seg_length - overlap_length

        # Store data as numpy arrays for fast indexing
        self._basin_data: Dict[str, Dict[str, np.ndarray]] = {}
        for basin_id, df in data.items():
            self._basin_data[basin_id] = {
                "main": df[main_features].values.astype(np.float32),
                "enc": df[enc_features].values.astype(np.float32),
                "target": df[[target]].values.astype(np.float32),
            }

        # Build lookup table: list of (basin_id, pred_k_start_idx)
        # pred_k_start_idx is the first index of predict_k (i.e. context_k ends here).
        self._lookup: List[tuple] = []
        for basin_id, arrays in self._basin_data.items():
            n_timesteps = len(arrays["target"])
            # context_k starts at (pred_k_start - context_length), so:
            #   min pred_k_start = context_length
            # predict_k+1 ends at (pred_k1_start + seg_length) where
            #   pred_k1_start = pred_k_start + step, so:
            #   max pred_k_start + step + seg_length <= n_timesteps
            #   max pred_k_start = n_timesteps - step - seg_length
            min_start = context_length
            max_start = n_timesteps - self._step - seg_length
            for i in range(min_start, max_start):
                y_k = arrays["target"][i:i + seg_length]
                pred_k1_start = i + self._step
                y_k1 = arrays["target"][pred_k1_start:pred_k1_start + seg_length]
                if not (np.any(np.isnan(y_k)) or np.any(np.isnan(y_k1))):
                    self._lookup.append((basin_id, i))

    def __len__(self) -> int:
        return len(self._lookup)

    def __getitem__(self, idx: int) -> Dict[str, torch.Tensor]:
        basin_id, pred_k_start = self._lookup[idx]
        arrays = self._basin_data[basin_id]

        # Seg k indices
        ctx_k_start = pred_k_start - self.context_length
        pred_k_end = pred_k_start + self.seg_length

        # Seg k+1 indices
        pred_k1_start = pred_k_start + self._step
        ctx_k1_start = pred_k1_start - self.context_length
        pred_k1_end = pred_k1_start + self.seg_length

        return {
            "context_k": torch.from_numpy(arrays["enc"][ctx_k_start:pred_k_start]),
            "predict_k": torch.from_numpy(arrays["main"][pred_k_start:pred_k_end]),
            "context_k1": torch.from_numpy(arrays["enc"][ctx_k1_start:pred_k1_start]),
            "predict_k1": torch.from_numpy(arrays["main"][pred_k1_start:pred_k1_end]),
            "y_k": torch.from_numpy(arrays["target"][pred_k_start:pred_k_end]),
            "y_k1": torch.from_numpy(arrays["target"][pred_k1_start:pred_k1_end]),
        }


class SingleSegDataset(Dataset):
    """Dataset that returns single segments for standard LSTM / encoder-only training.

    Each sample is one segment with optional encoder context window.

    Parameters
    ----------
    data : dict
        Mapping basin_id -> DataFrame with features + target columns.
    seg_length : int
        Prediction segment length in timesteps.
    main_features : list
        Feature columns for the main LSTM.
    target : str
        Target column name.
    context_length : int, optional
        If > 0, each sample also includes a context window for the encoder.
    enc_features : list, optional
        Feature columns for the encoder (required if context_length > 0).
    """

    def __init__(self, data: Dict[str, pd.DataFrame], seg_length: int,
                 main_features: List[str], target: str,
                 context_length: int = 0, enc_features: Optional[List[str]] = None):
        super().__init__()
        self.seg_length = seg_length
        self.context_length = context_length
        self.main_features = main_features
        self.target = target
        self.enc_features = enc_features
        self._has_context = context_length > 0 and enc_features is not None

        self._basin_data: Dict[str, Dict[str, np.ndarray]] = {}
        for basin_id, df in data.items():
            entry = {
                "main": df[main_features].values.astype(np.float32),
                "target": df[[target]].values.astype(np.float32),
            }
            if self._has_context:
                entry["enc"] = df[enc_features].values.astype(np.float32)
            self._basin_data[basin_id] = entry

        self._lookup: List[tuple] = []
        for basin_id, arrays in self._basin_data.items():
            n = len(arrays["target"])
            min_start = max(context_length, 0)
            for i in range(min_start, n - seg_length):
                y = arrays["target"][i:i + seg_length]
                if not np.any(np.isnan(y)):
                    self._lookup.append((basin_id, i))

    def __len__(self) -> int:
        return len(self._lookup)

    def __getitem__(self, idx: int) -> Dict[str, torch.Tensor]:
        basin_id, start = self._lookup[idx]
        arrays = self._basin_data[basin_id]
        sample = {
            "x": torch.from_numpy(arrays["main"][start:start + self.seg_length]),
            "y": torch.from_numpy(arrays["target"][start:start + self.seg_length]),
        }
        if self._has_context:
            ctx_start = start - self.context_length
            sample["context"] = torch.from_numpy(arrays["enc"][ctx_start:start])
        return sample
