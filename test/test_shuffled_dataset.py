"""Tests for shuffled dataset functions."""
import sys
from pathlib import Path

import pytest
import torch

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))


def test_shuffled_dataset_remaps_attributes():
    """apply_shuffle replaces basin attributes according to shuffle_map."""
    from static_falsification.shuffled_dataset import apply_shuffle

    attrs = {
        "basin_a": torch.tensor([1.0, 2.0]),
        "basin_b": torch.tensor([3.0, 4.0]),
        "basin_c": torch.tensor([5.0, 6.0]),
    }
    shuffle_map = {"basin_a": "basin_b", "basin_b": "basin_c", "basin_c": "basin_a"}

    result = apply_shuffle(dict(attrs), shuffle_map)

    assert torch.equal(result["basin_a"], attrs["basin_b"])
    assert torch.equal(result["basin_b"], attrs["basin_c"])
    assert torch.equal(result["basin_c"], attrs["basin_a"])


def test_apply_constant_zeros_all_attributes():
    """apply_constant replaces all attributes with zeros."""
    from static_falsification.shuffled_dataset import apply_constant

    attrs = {
        "basin_a": torch.tensor([1.0, 2.0, 3.0]),
        "basin_b": torch.tensor([4.0, 5.0, 6.0]),
    }

    result = apply_constant(dict(attrs))

    for basin, tensor in result.items():
        assert torch.equal(tensor, torch.zeros(3))
