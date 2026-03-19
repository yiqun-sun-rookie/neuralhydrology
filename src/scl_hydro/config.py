"""SCLConfig — wraps neuralhydrology Config with SCL-specific parameters.

SCLConfig does NOT subclass Config (Config validates keys and rejects unknowns).
Instead it extracts SCL-specific keys from the raw dict, stores them internally,
and passes the remaining keys to Config with ``dev_mode=True``.
"""
from pathlib import Path
from typing import Any, Dict, List, Union

from neuralhydrology.utils.config import Config

# SCL-specific parameter names and their defaults.
_SCL_DEFAULTS: Dict[str, Any] = {
    "seg_length": 180,
    "context_length": 30,
    "overlap_length": 30,
    "scl_weight": 0.1,
    "enc_hidden_size": 64,
    "encoder_inputs": [],
}


class SCLConfig:
    """Configuration for SCL-LSTM experiments.

    Wraps :class:`neuralhydrology.utils.config.Config` and adds SCL-specific
    parameters (segment length, context window, overlap, loss weight, encoder
    hidden size, encoder inputs).

    Parameters
    ----------
    yml_path_or_dict : Union[Path, str, dict]
        A YAML file path or a raw configuration dictionary.  SCL-specific keys
        are extracted before the remainder is forwarded to the NH Config.

    Raises
    ------
    ValueError
        If ``overlap_length >= seg_length``.
    """

    def __init__(self, yml_path_or_dict: Union[Path, str, dict]) -> None:
        # Materialise dict from YAML if needed.
        if isinstance(yml_path_or_dict, (str, Path)):
            from ruamel.yaml import YAML
            yaml = YAML()
            with open(yml_path_or_dict, "r", encoding="utf-8") as fp:
                raw: dict = yaml.load(fp)
        elif isinstance(yml_path_or_dict, dict):
            raw = yml_path_or_dict.copy()
        else:
            raise ValueError(
                f"Expected Path, str, or dict; got {type(yml_path_or_dict)}"
            )

        # Extract SCL keys (use defaults for missing ones).
        self._scl: Dict[str, Any] = {}
        for key, default in _SCL_DEFAULTS.items():
            self._scl[key] = raw.pop(key, default)

        # Copy list defaults so mutations don't leak across instances.
        if isinstance(self._scl["encoder_inputs"], list):
            self._scl["encoder_inputs"] = list(self._scl["encoder_inputs"])

        # --- validation ---
        if self._scl["overlap_length"] >= self._scl["seg_length"]:
            raise ValueError(
                f"overlap_length ({self._scl['overlap_length']}) must be "
                f"strictly less than seg_length ({self._scl['seg_length']})."
            )

        # Build NH Config from the remaining dict (dev_mode to tolerate any
        # unknown keys that NH does not recognise).
        self._nh_config = Config(raw, dev_mode=True)

    # ---- SCL-specific properties ----------------------------------------

    @property
    def seg_length(self) -> int:
        """Prediction segment length in days."""
        return self._scl["seg_length"]

    @property
    def context_length(self) -> int:
        """Encoder context window length."""
        return self._scl["context_length"]

    @property
    def overlap_length(self) -> int:
        """Overlap between adjacent segments."""
        return self._scl["overlap_length"]

    @property
    def scl_weight(self) -> float:
        """State continuity loss weight (lambda)."""
        return self._scl["scl_weight"]

    @property
    def enc_hidden_size(self) -> int:
        """Encoder LSTM hidden size."""
        return self._scl["enc_hidden_size"]

    @property
    def encoder_inputs(self) -> List[str]:
        """Additional encoder input features."""
        return self._scl["encoder_inputs"]

    @property
    def overlap_start(self) -> int:
        """Index where the overlap region begins (``seg_length - overlap_length``)."""
        return self._scl["seg_length"] - self._scl["overlap_length"]

    # ---- delegation to NH Config ----------------------------------------

    def __getattr__(self, name: str) -> Any:
        """Delegate attribute access to the underlying NH Config."""
        # __getattr__ is only called when normal attribute lookup fails,
        # so _nh_config will not recurse during __init__.
        return getattr(self._nh_config, name)
