import hashlib
import json
from pathlib import Path
import sys

import numpy as np
import pytest
import torch


IDEA_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IDEA_ROOT))


def test_v09_edges_cover_every_historical_lag_once():
    from bands_formal_v09 import history_edges_v09

    edges = history_edges_v09()
    widths = np.diff(edges)
    payload = json.dumps(edges.tolist(), separators=(",", ":")).encode("utf-8")
    covered = np.concatenate([
        np.arange(int(edges[index]), int(edges[index + 1]))
        for index in range(120)
    ])

    assert edges.shape == (121,)
    assert (edges[0], edges[-1]) == (270, 3_562)
    assert np.all(widths > 0)
    assert (int(widths.min()), int(widths.max()), int(widths.sum())) == (6, 76, 3_292)
    assert hashlib.sha256(payload).hexdigest() == (
        "55bbdaf654e7ea2b8959cc5dd62de98e4631c272ffe9d7f4efeae9cb7240927b"
    )
    np.testing.assert_array_equal(covered, np.arange(270, 3_562))


def test_v09_gather_reads_only_one_chronological_causal_batch():
    from bands_formal_v09 import gather_causal_windows_v09
    from memory_safety_v09 import HostMemorySnapshot, MemorySafetyGate

    time = np.arange(4_000, dtype=np.float32)
    forcing = np.stack([time + 10_000 * feature for feature in range(5)], axis=-1)
    forcing = np.stack((forcing, forcing + np.float32(100_000)), axis=0)
    snapshot = HostMemorySnapshot(
        32 * 2**30,
        20 * 2**30,
        256 * 2**20,
        40 * 2**30,
    )
    windows = gather_causal_windows_v09(
        forcing,
        np.array([0, 1]),
        np.array([3_561, 3_999]),
        gate=MemorySafetyGate.from_snapshot(snapshot),
        snapshot=snapshot,
    )

    assert windows.shape == (2, 3_562, 5)
    np.testing.assert_array_equal(windows[0, :, 0], np.arange(3_562, dtype=np.float32))
    np.testing.assert_array_equal(
        windows[1, :, 0],
        np.arange(438, 4_000, dtype=np.float32) + 100_000,
    )


def test_v09_gather_rejects_missing_history_and_non_float32_source():
    from bands_formal_v09 import gather_causal_windows_v09

    forcing = np.zeros((1, 4_000, 5), dtype=np.float32)
    with pytest.raises(ValueError, match="at least 3561"):
        gather_causal_windows_v09(forcing, np.array([0]), np.array([3_560]))
    with pytest.raises(ValueError, match="float32"):
        gather_causal_windows_v09(forcing.astype(np.float64), np.array([0]), np.array([3_561]))


def test_v09_split_is_causal_chronological_and_uses_exact_bin_means():
    from bands_formal_v09 import history_edges_v09, split_windows_v09

    time = torch.arange(3_562, dtype=torch.float64)
    windows = torch.stack([time + 10_000 * feature for feature in range(5)], dim=-1)[None, :, :]
    dynamic = split_windows_v09(windows)

    assert dynamic["recent"].shape == (1, 270, 5)
    assert dynamic["history"].shape == (1, 120, 7)
    torch.testing.assert_close(
        dynamic["recent"][0, :, 0],
        torch.arange(3_292, 3_562, dtype=torch.float64),
        rtol=0,
        atol=0,
    )
    edges = history_edges_v09()
    for sequence_index, edge_index in enumerate(reversed(range(120))):
        low = int(edges[edge_index])
        high = int(edges[edge_index + 1])
        expected = windows[0, 3_562 - high:3_562 - low].mean(dim=0)
        torch.testing.assert_close(
            dynamic["history"][0, sequence_index, :5],
            expected,
            rtol=0,
            atol=1e-10,
        )
    assert dynamic["history"][0, 0, 6] > dynamic["history"][0, -1, 6]


def test_v09_split_does_not_call_torch_cumsum(monkeypatch):
    from bands_formal_v09 import split_windows_v09

    def reject_cumsum(*_args, **_kwargs):
        raise AssertionError("split_windows_v09 must not call the nondeterministic CUDA cumsum kernel")

    monkeypatch.setattr(torch, "cumsum", reject_cumsum)
    windows = torch.arange(3_562 * 5, dtype=torch.float32).reshape(1, 3_562, 5)
    dynamic = split_windows_v09(windows)

    assert dynamic["recent"].shape == (1, 270, 5)
    assert dynamic["history"].shape == (1, 120, 7)


@pytest.mark.skipif(not torch.cuda.is_available(), reason="CUDA is required for the strict determinism regression")
def test_v09_cuda_prefix_sum_is_strictly_deterministic_and_matches_native_cumsum():
    from bands_formal_v09 import _deterministic_cumsum_dim1_v09

    deterministic_before = torch.are_deterministic_algorithms_enabled()
    warn_only_before = torch.is_deterministic_algorithms_warn_only_enabled()
    try:
        torch.manual_seed(26_090)
        values = torch.randn(4, 3_562, 5, device="cuda", dtype=torch.float32)
        torch.use_deterministic_algorithms(False)
        native = torch.cumsum(values, dim=1)

        torch.use_deterministic_algorithms(True)
        first = _deterministic_cumsum_dim1_v09(values)
        second = _deterministic_cumsum_dim1_v09(values)

        assert torch.equal(first, second)
        assert torch.equal(first, native)
    finally:
        torch.use_deterministic_algorithms(deterministic_before, warn_only=warn_only_before)


def test_v09_split_rejects_a_batch_above_the_frozen_memory_bound():
    from bands_formal_v09 import split_windows_v09

    oversized = torch.empty((257, 3_562, 5), device="meta")
    with pytest.raises(ValueError, match="1 through 256"):
        split_windows_v09(oversized)
