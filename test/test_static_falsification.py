"""Tests for static falsification experiment utilities."""
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))


def test_generate_fold_splits():
    """5-fold split covers all 531 basins with no overlap."""
    from static_falsification.scripts.generate_splits import generate_fold_splits

    basins = [f"{i:08d}" for i in range(531)]
    folds = generate_fold_splits(basins, n_folds=5, seed=42)

    assert len(folds) == 5
    all_basins = []
    for fold in folds:
        assert len(fold) > 0
        all_basins.extend(fold)
    assert sorted(all_basins) == sorted(basins), "Folds must cover all basins exactly once"


def test_generate_derangement():
    """Derangement has no fixed points."""
    from static_falsification.scripts.generate_splits import generate_derangement

    items = [f"{i:08d}" for i in range(100)]
    mapping = generate_derangement(items, seed=42)

    assert len(mapping) == len(items)
    for k, v in mapping.items():
        assert k != v, f"Fixed point found: {k} -> {v}"
    assert set(mapping.values()) == set(items), "Derangement must be a permutation"


def test_generate_derangement_deterministic():
    """Same seed produces same derangement."""
    from static_falsification.scripts.generate_splits import generate_derangement

    items = [f"{i:08d}" for i in range(50)]
    m1 = generate_derangement(items, seed=99)
    m2 = generate_derangement(items, seed=99)
    assert m1 == m2
