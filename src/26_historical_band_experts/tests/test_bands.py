from pathlib import Path
import sys

import numpy as np
import torch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from bands import fixed_band_specs, gather_fixed_bands, lag_bin_edges


def test_fixed_bands_are_disjoint_complete_and_causal():
    specs = fixed_band_specs()
    covered = np.concatenate([
        np.arange(spec.start_lag, spec.end_lag + 1, dtype=np.int64)
        for spec in specs
    ])

    assert [spec.name for spec in specs] == ["recent", "medium", "old"]
    assert covered.min() == 0
    assert covered.max() == 3649
    assert len(covered) == 3650
    assert len(np.unique(covered)) == 3650


def test_lag_bin_edges_cover_every_day_once():
    for spec in fixed_band_specs():
        edges = lag_bin_edges(spec)
        assert edges[0] == spec.start_lag
        assert edges[-1] == spec.end_lag + 1
        assert len(edges) == spec.bins + 1
        assert np.all(np.diff(edges) > 0)
        assert int(np.diff(edges).sum()) == spec.end_lag - spec.start_lag + 1


def test_gather_fixed_bands_is_chronological_and_matches_manual_means():
    x = torch.arange(4000, dtype=torch.float32).reshape(1, 4000, 1)
    bands = gather_fixed_bands(
        x,
        basin_indices=torch.tensor([0]),
        target_indices=torch.tensor([3649]),
    )

    assert bands["recent"].shape == (1, 30, 1)
    assert bands["medium"].shape == (1, 60, 1)
    assert bands["old"].shape == (1, 60, 1)
    torch.testing.assert_close(
        bands["recent"][0, :, 0],
        torch.arange(3620, 3650, dtype=torch.float32),
    )

    target = 3649
    for spec in fixed_band_specs()[1:]:
        edges = lag_bin_edges(spec)
        expected = []
        for index in reversed(range(spec.bins)):
            low_lag = int(edges[index])
            high_lag_exclusive = int(edges[index + 1])
            values = np.arange(
                target - high_lag_exclusive + 1,
                target - low_lag + 1,
                dtype=np.float32,
            )
            expected.append(float(values.mean()))
        np.testing.assert_allclose(
            bands[spec.name][0, :, 0].numpy(),
            np.asarray(expected, dtype=np.float32),
            rtol=0,
            atol=1e-5,
        )


def test_future_values_cannot_change_extracted_bands():
    generator = torch.Generator().manual_seed(17)
    x = torch.randn(2, 4010, 3, generator=generator)
    basin_indices = torch.tensor([0, 1])
    target_indices = torch.tensor([3649, 3650])
    before = gather_fixed_bands(x, basin_indices, target_indices)

    changed = x.clone()
    changed[0, 3650:, :] = 1_000_000.0
    changed[1, 3651:, :] = -1_000_000.0
    after = gather_fixed_bands(changed, basin_indices, target_indices)

    for name in before:
        torch.testing.assert_close(before[name], after[name])


def test_target_without_full_history_is_rejected():
    x = torch.zeros(1, 3650, 2)
    with np.testing.assert_raises_regex(ValueError, "3649"):
        gather_fixed_bands(x, torch.tensor([0]), torch.tensor([3648]))
