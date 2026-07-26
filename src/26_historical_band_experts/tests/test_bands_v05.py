from pathlib import Path
import sys

import numpy as np
import pytest
import torch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from bands_v03 import fixed_band_specs_v03, lag_bin_edges
from bands_v05 import gather_rich_bands_v05


def _manual_statistics(values: torch.Tensor) -> torch.Tensor:
    return torch.cat(
        (
            values.mean(dim=0),
            values.std(dim=0, unbiased=False),
            values.amin(dim=0),
            values.amax(dim=0),
        )
    )


def test_v05_rich_bands_have_frozen_shapes_and_old_hierarchy():
    generator = torch.Generator().manual_seed(51)
    x = torch.randn(2, 4000, 5, generator=generator)
    bands = gather_rich_bands_v05(
        x,
        basin_indices=torch.tensor([0, 1]),
        target_indices=torch.tensor([3649, 3700]),
    )

    assert tuple(bands) == ("recent", "medium", "old")
    assert bands["recent"].shape == (2, 270, 5)
    assert bands["medium"].shape == (2, 60, 20)
    assert bands["old"].shape == (2, 5, 12, 20)


def test_v05_statistics_match_manual_blocks_in_chronological_order():
    features = torch.stack(
        (
            torch.arange(4000, dtype=torch.float32),
            2.0 * torch.arange(4000, dtype=torch.float32) - 7.0,
        ),
        dim=-1,
    ).unsqueeze(0)
    target = 3649
    bands = gather_rich_bands_v05(features, torch.tensor([0]), torch.tensor([target]))

    for name, values in (("medium", bands["medium"]), ("old", bands["old"].reshape(1, 60, 8))):
        spec = next(spec for spec in fixed_band_specs_v03() if spec.name == name)
        edges = lag_bin_edges(spec)
        for output_index, bin_index in enumerate(reversed(range(spec.bins))):
            low_lag = int(edges[bin_index])
            high_lag_exclusive = int(edges[bin_index + 1])
            raw = features[
                0,
                target - high_lag_exclusive + 1:target - low_lag + 1,
            ]
            torch.testing.assert_close(
                values[0, output_index],
                _manual_statistics(raw),
                rtol=0,
                atol=1e-5,
            )


def test_v05_constant_blocks_have_population_std_zero_and_are_finite():
    x = torch.full((1, 4000, 3), 7.25)
    bands = gather_rich_bands_v05(x, torch.tensor([0]), torch.tensor([3649]))

    for name in ("medium", "old"):
        flattened = bands[name].reshape(1, 60, 12)
        mean, std, minimum, maximum = flattened.chunk(4, dim=-1)
        torch.testing.assert_close(mean, torch.full_like(mean, 7.25))
        torch.testing.assert_close(std, torch.zeros_like(std))
        torch.testing.assert_close(minimum, torch.full_like(minimum, 7.25))
        torch.testing.assert_close(maximum, torch.full_like(maximum, 7.25))
        assert torch.isfinite(flattened).all()


def test_v05_future_values_cannot_change_any_band():
    generator = torch.Generator().manual_seed(52)
    x = torch.randn(2, 4010, 3, generator=generator)
    basin_indices = torch.tensor([0, 1])
    target_indices = torch.tensor([3649, 3650])
    before = gather_rich_bands_v05(x, basin_indices, target_indices)

    changed = x.clone()
    changed[0, 3650:] = 1_000_000.0
    changed[1, 3651:] = -1_000_000.0
    after = gather_rich_bands_v05(changed, basin_indices, target_indices)

    for name in before:
        torch.testing.assert_close(before[name], after[name])


def test_v05_old_reshape_preserves_all_sixty_time_blocks():
    x = torch.arange(4000, dtype=torch.float32).reshape(1, 4000, 1)
    old = gather_rich_bands_v05(x, torch.tensor([0]), torch.tensor([3649]))["old"]
    flattened_means = old[..., 0].reshape(-1)
    assert flattened_means.shape == (60,)
    assert torch.all(torch.diff(flattened_means) > 0)


def test_v05_rejects_target_without_full_ten_year_history():
    x = torch.zeros(1, 3650, 2)
    with pytest.raises(ValueError, match="3649"):
        gather_rich_bands_v05(x, torch.tensor([0]), torch.tensor([3648]))


def test_v05_rejects_non_three_dimensional_forcing():
    with pytest.raises(ValueError, match="shape"):
        gather_rich_bands_v05(torch.zeros(10, 2), torch.tensor([0]), torch.tensor([3649]))
