"""Dataset subclass that shuffles or zeroes static catchment attributes."""
from typing import Dict

import torch
from neuralhydrology.datasetzoo.camelsus import CamelsUS


def apply_shuffle(attributes: Dict[str, torch.Tensor],
                  shuffle_map: Dict[str, str]) -> Dict[str, torch.Tensor]:
    """Remap basin->attributes according to shuffle_map.

    Parameters
    ----------
    attributes : dict
        Original mapping of basin_id -> attribute tensor.
    shuffle_map : dict
        Mapping of basin_id -> source_basin_id (the basin whose attributes to use).

    Returns
    -------
    dict
        New mapping with remapped attributes.
    """
    original = dict(attributes)
    result = {}
    for basin, source in shuffle_map.items():
        if basin in original and source in original:
            result[basin] = original[source]
    # Keep any basins not in the shuffle_map unchanged
    for basin in original:
        if basin not in result:
            result[basin] = original[basin]
    return result


def apply_constant(attributes: Dict[str, torch.Tensor]) -> Dict[str, torch.Tensor]:
    """Replace all basin attributes with zero vectors (global mean after z-score).

    Parameters
    ----------
    attributes : dict
        Original mapping of basin_id -> attribute tensor.

    Returns
    -------
    dict
        New mapping with all-zeros tensors.
    """
    return {basin: torch.zeros_like(tensor) for basin, tensor in attributes.items()}


class ModifiedCamelsUS(CamelsUS):
    """CamelsUS variant that applies shuffle or constant to static attributes after loading.

    Set class-level variables before instantiation:
        ModifiedCamelsUS._shuffle_map = {...}  # for shuffle mode
        ModifiedCamelsUS._constant_mode = True  # for constant (zero) mode
    """

    _shuffle_map = None
    _constant_mode = False

    def _load_data(self):
        super()._load_data()
        if self._attributes:
            if self.__class__._constant_mode:
                self._attributes = apply_constant(self._attributes)
            elif self.__class__._shuffle_map:
                self._attributes = apply_shuffle(self._attributes, self.__class__._shuffle_map)
