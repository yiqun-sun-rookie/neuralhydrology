"""Contract tests for the stage-1 online noise pilot (no filter runs)."""

import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from camels_switch_confirmation.run_online_noise_pilot import (  # noqa: E402
    A1_C_BOUNDS,
    A1_M_BOUNDS,
    A1_STEP_CLIP,
    ORACLE_CELL,
    Z2_WINSOR,
    a1_update,
    bma_log_weights,
    combine_log_posteriors,
    grid_cells,
    pilot_tasks,
)


def test_grid_has_15_cells_including_oracle():
    cells = grid_cells()
    assert len(cells) == 15
    assert len(set(cells)) == 15
    assert ORACLE_CELL in cells


def test_pilot_task_list_is_16_tasks():
    tasks = pilot_tasks()
    assert len(tasks) == 16
    assert len(set(tasks)) == 16
    arms = {arm for _, _, arm in tasks}
    seeds = {seed for _, seed, _ in tasks}
    assert arms == {"C", "P"}
    assert seeds == {0, 1}
    assert sum(1 for b, _, _ in tasks if b == "07184000") == 4


def test_a1_update_no_change_without_z2():
    state = (0.5, 0.1, 1.0, 1.0)
    assert a1_update(*state, None, False) == state
    assert a1_update(*state, float("nan"), True) == state


def test_a1_update_step_is_clipped_and_bounded():
    m, c, ewma_dry, ewma_rain = a1_update(1.0, 0.2, 1.0, 1.0, Z2_WINSOR * 10, False)
    assert m <= 1.0 * A1_STEP_CLIP[1] + 1e-12
    assert c == 0.2
    assert ewma_rain == 1.0
    assert math.isclose(ewma_dry, 0.98 * 1.0 + 0.02 * Z2_WINSOR)
    m, c, *_ = a1_update(A1_M_BOUNDS[1], A1_C_BOUNDS[1], 1e9, 1e9, 50.0, True)
    assert c <= A1_C_BOUNDS[1]
    tiny = a1_update(A1_M_BOUNDS[0], A1_C_BOUNDS[0], 1e-12, 1e-12, 1e-12, False)
    assert tiny[0] >= A1_M_BOUNDS[0]


def test_bma_weights_are_causal_and_normalized():
    rng = np.random.default_rng(0)
    loglik = rng.normal(size=(4, 30))
    for forget in (None, 0.99):
        base = bma_log_weights(loglik, forget)
        assert np.allclose(np.exp(base).sum(axis=0), 1.0)
        perturbed = loglik.copy()
        perturbed[:, 20:] += rng.normal(size=(4, 10)) * 5.0
        after = bma_log_weights(perturbed, forget)
        assert np.allclose(base[:, :20], after[:, :20])


def test_combine_log_posteriors_matches_linear_mixture():
    rng = np.random.default_rng(1)
    logw = np.log(rng.dirichlet(np.ones(3), size=5).T)  # (3 configs, 5 days)
    posts = rng.dirichlet(np.ones(4), size=(3, 5))  # (3, 5, 4)
    combined = np.exp(combine_log_posteriors(logw, np.log(posts)))
    direct = np.einsum("gt,gtk->tk", np.exp(logw), posts)
    assert np.allclose(combined, direct)


def test_combine_log_posteriors_handles_neg_inf():
    logw = np.array([[0.0, math.log(0.5)], [-np.inf, math.log(0.5)]])
    posts = np.log(np.array([[[1.0, 0.0], [0.5, 0.5]], [[0.2, 0.8], [0.0, 1.0]]]))
    combined = combine_log_posteriors(logw, posts)
    assert combined[0, 1] == -np.inf
    assert np.isclose(np.exp(combined)[1, 1], 0.75)
