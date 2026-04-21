"""End-to-end integration tests for MockLLM Rules 1, 2, and 4.

Each test verifies the full agent signal chain:
  deficient initial model → diagnosis detects the issue → MockLLM proposes fix → NSE improves

Rules tested:
  - Rule 1: NSE < 0.3 → add RoutingStore(baseflow)
  - Rule 2: Peak_Lag > 3.0 → remove lag_functions
  - Rule 4: Low_Flow_Bias < -0.3 → add LinearReservoir(slow_gw)
"""

import unittest
import sys
import os
from copy import deepcopy

import numpy as np
import pandas as pd

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))

from hydroagent.agent import HydroAgent, MockLLMClient, DEFAULT_INITIAL_STRUCTURE
from hydroagent.environment import SuperflexEnv, _LAG_REGISTRY


# ---------------------------------------------------------------------------
# Synthetic data generators
# ---------------------------------------------------------------------------

def _make_forcing(n_days=730, seed=42):
    """Create 2-year daily forcing with seasonal temperature and precipitation."""
    rng = np.random.RandomState(seed)
    dates = pd.date_range('2000-01-01', periods=n_days, freq='D')
    doy = dates.dayofyear.values

    tmean = 10.0 + 15.0 * np.sin(2 * np.pi * (doy - 100) / 365) + rng.normal(0, 2, n_days)
    prcp = rng.exponential(3.0, n_days)
    prcp[np.isin(dates.month, [12, 1, 2])] *= 1.5
    ep = np.maximum(2.5 + 2.5 * np.sin(2 * np.pi * (doy - 100) / 365), 0.0)

    return pd.DataFrame({'prcp': prcp, 'ep': ep, 'tmean': tmean}, index=dates), rng


def _make_forcing_with_dry_spells(n_days=730, seed=42):
    """Forcing with reduced summer precipitation to amplify low-flow signals."""
    forcing, rng = _make_forcing(n_days, seed)
    dry_mask = np.isin(forcing.index.month, [7, 8])
    forcing.loc[dry_mask, 'prcp'] *= 0.1
    return forcing, rng


# ---------------------------------------------------------------------------
# Truth obs generators
# ---------------------------------------------------------------------------

def _make_two_component_obs(forcing, rng):
    """Generate obs with two distinct timescales: immediate + slow linear reservoir.

    Physics: a fast direct-response component (15% of rain) plus a slow
    groundwater reservoir (k=0.01, time constant ~100 days). A single
    PowerReservoir cannot simultaneously produce sharp peaks AND persistent
    baseflow, so the DEFAULT model gets NSE < 0.3.
    """
    prcp = forcing['prcp'].values
    n = len(prcp)

    fast_comp = 0.15 * prcp

    storage = 0.0
    slow_comp = np.zeros(n)
    for i in range(n):
        storage += 0.5 * prcp[i]
        release = 0.01 * storage
        slow_comp[i] = release
        storage -= release

    obs = fast_comp + slow_comp + rng.normal(0, 0.1, n)
    return pd.Series(np.maximum(obs, 0.01), index=forcing.index)


def _make_slowgw_obs(forcing, rng):
    """Generate obs with 50% slow groundwater via SuperflexPy inverse crime.

    Truth: soil + fast(k=0.3, very fast) + slow_gw(k=0.005, very slow), split 50/50.
    DEFAULT (fast-only) matches peaks but underestimates dry-period baseflow
    → Low_Flow_Bias < -0.3 while NSE >= 0.3.
    """
    structure = {
        'model_name': 'truth_slowgw',
        'layers': [
            {'id': 'soil', 'type': 'UnsaturatedReservoir',
             'inputs': ['prcp', 'ep'], 'parameters': ['Smax', 'Ce', 'm', 'beta']},
            {'id': 'fast', 'type': 'PowerReservoir',
             'inputs': ['soil.runoff'], 'parameters': ['k', 'alpha']},
            {'id': 'slow_gw', 'type': 'LinearReservoir',
             'inputs': ['soil.runoff'], 'parameters': ['k']},
        ],
        'lag_functions': [],
        'system_output': ['fast', 'slow_gw'],
    }
    env = SuperflexEnv()
    env.parse_structure(structure)
    params = {
        'soil_Smax': 200.0, 'soil_Ce': 1.0, 'soil_m': 0.01, 'soil_beta': 2.0,
        'fast_k': 0.3, 'fast_alpha': 2.0,
        'slowgw_k': 0.005,
        '__split_soil': 0.5,
    }
    obs = env.run_simulation(forcing, params=params)
    return pd.Series((obs.values + rng.normal(0, 0.05, len(obs))).clip(min=0.01),
                      index=forcing.index)


# ---------------------------------------------------------------------------
# Test class: Rule 1 — Baseflow (NSE < 0.3 → add RoutingStore)
# ---------------------------------------------------------------------------

class TestRule1BaseflowE2E(unittest.TestCase):
    """E2E: two-component obs → NSE < 0.3 → add RoutingStore → NSE improves."""

    _orig_calibrate = None

    def setUp(self):
        TestRule1BaseflowE2E._orig_calibrate = SuperflexEnv._calibrate_sfpy

        def _fast_calibrate(self_env, forcing, obs, n_trials=50):
            return TestRule1BaseflowE2E._orig_calibrate(self_env, forcing, obs, n_trials=50)

        SuperflexEnv._calibrate_sfpy = _fast_calibrate

    def tearDown(self):
        if TestRule1BaseflowE2E._orig_calibrate is not None:
            SuperflexEnv._calibrate_sfpy = TestRule1BaseflowE2E._orig_calibrate

    def test_solve_inserts_baseflow(self):
        forcing, rng = _make_forcing()
        obs = _make_two_component_obs(forcing, rng)

        agent = HydroAgent(llm_client=MockLLMClient(), max_iterations=3)
        result = agent.solve(forcing, obs, target_nse=0.99)

        # A1: Initial NSE should be poor (< 0.3)
        init_nse = agent.history[0]['nse']
        self.assertLess(init_nse, 0.3,
                        f"Initial NSE should be < 0.3 without baseflow, got {init_nse:.3f}")

        # A2: RoutingStore should appear in some iteration
        has_routing = False
        for entry in agent.history:
            layer_types = {l['type'] for l in entry['structure'].get('layers', [])}
            if 'RoutingStore' in layer_types:
                has_routing = True
                break
        self.assertTrue(has_routing, "RoutingStore should be inserted within 3 iterations")

        # A3: NSE should improve by at least 0.1
        self.assertGreater(result['best_nse'], init_nse + 0.1,
                           f"best_nse ({result['best_nse']:.3f}) should improve over "
                           f"initial ({init_nse:.3f}) by at least 0.1")


# ---------------------------------------------------------------------------
# Test class: Rule 2 — Remove Lag (Peak_Lag > 3 → clear lag_functions)
# ---------------------------------------------------------------------------

class TestRule2RemoveLagE2E(unittest.TestCase):
    """E2E: no-lag obs + lagged initial → Peak_Lag > 3 → remove lag → NSE improves."""

    _orig_calibrate = None
    _orig_lag_bounds = None

    def setUp(self):
        TestRule2RemoveLagE2E._orig_calibrate = SuperflexEnv._calibrate_sfpy

        def _fast_calibrate(self_env, forcing, obs, n_trials=50):
            return TestRule2RemoveLagE2E._orig_calibrate(self_env, forcing, obs, n_trials=50)

        SuperflexEnv._calibrate_sfpy = _fast_calibrate

        # Fix lag to 10 timesteps (effectively non-calibratable via narrow bounds).
        # With lag=10, calibrator compensates via soil/fast params but residual
        # Peak_Lag ≈ 5.8 > 3.0 (Rule 2 threshold), while NSE ≈ 0.66 > 0.3.
        TestRule2RemoveLagE2E._orig_lag_bounds = _LAG_REGISTRY['HalfTriangularLag']['bounds']
        _LAG_REGISTRY['HalfTriangularLag']['bounds'] = (10.0, 10.01)

    def tearDown(self):
        if TestRule2RemoveLagE2E._orig_calibrate is not None:
            SuperflexEnv._calibrate_sfpy = TestRule2RemoveLagE2E._orig_calibrate
        if TestRule2RemoveLagE2E._orig_lag_bounds is not None:
            _LAG_REGISTRY['HalfTriangularLag']['bounds'] = TestRule2RemoveLagE2E._orig_lag_bounds

    def test_solve_removes_lag(self):
        forcing, rng = _make_forcing()

        # Generate obs from DEFAULT structure (no lag)
        env = SuperflexEnv()
        env.parse_structure(DEFAULT_INITIAL_STRUCTURE)
        obs = env.run_simulation(forcing)
        obs = pd.Series((obs.values + rng.normal(0, 0.05, len(obs))).clip(min=0.01),
                         index=forcing.index)

        # Start from a lagged initial structure
        lagged_initial = deepcopy(DEFAULT_INITIAL_STRUCTURE)
        lagged_initial['lag_functions'] = [
            {'type': 'HalfTriangularLag', 'target': 'fast', 'lag_steps': 10}
        ]
        lagged_initial['model_name'] = 'v0_lagged'

        agent = HydroAgent(llm_client=MockLLMClient(), max_iterations=3)
        result = agent.solve(forcing, obs, target_nse=0.99,
                             initial_structure=lagged_initial)

        # A1: Initial Peak_Lag should be > 3.0
        iter1 = agent.history[0]
        peak_lag = iter1['report']['metrics'].get('Peak_Lag_Hours', 0.0)
        self.assertGreater(peak_lag, 3.0,
                           f"Iteration 1 Peak_Lag should be > 3.0, got {peak_lag:.1f}")

        # A2: lag_functions should be cleared in some iteration after the first
        lag_cleared = False
        for entry in agent.history[1:]:
            if entry['structure'].get('lag_functions') == []:
                lag_cleared = True
                break
        self.assertTrue(lag_cleared, "lag_functions should be cleared in some iteration")

        # A3: NSE should improve
        init_nse = agent.history[0]['nse']
        self.assertGreater(result['best_nse'], init_nse,
                           f"best_nse ({result['best_nse']:.3f}) should improve over "
                           f"initial ({init_nse:.3f})")


# ---------------------------------------------------------------------------
# Test class: Rule 4 — Slow Groundwater (Low_Flow_Bias < -0.3 → add slow_gw)
# ---------------------------------------------------------------------------

class TestRule4SlowGWE2E(unittest.TestCase):
    """E2E: slow_gw obs → Low_Flow_Bias < -0.3 → add slow_gw → NSE improves."""

    _orig_calibrate = None

    def setUp(self):
        TestRule4SlowGWE2E._orig_calibrate = SuperflexEnv._calibrate_sfpy

        def _fast_calibrate(self_env, forcing, obs, n_trials=50):
            return TestRule4SlowGWE2E._orig_calibrate(self_env, forcing, obs, n_trials=50)

        SuperflexEnv._calibrate_sfpy = _fast_calibrate

    def tearDown(self):
        if TestRule4SlowGWE2E._orig_calibrate is not None:
            SuperflexEnv._calibrate_sfpy = TestRule4SlowGWE2E._orig_calibrate

    def test_solve_inserts_slow_gw(self):
        forcing, rng = _make_forcing_with_dry_spells()
        obs = _make_slowgw_obs(forcing, rng)

        agent = HydroAgent(llm_client=MockLLMClient(), max_iterations=3)
        result = agent.solve(forcing, obs, target_nse=0.99)

        init_nse = agent.history[0]['nse']
        init_metrics = agent.history[0]['report']['metrics']

        # A1: Initial NSE should be >= 0.3 (so Rule 1 doesn't trigger first)
        self.assertGreaterEqual(init_nse, 0.3,
                                f"Initial NSE should be >= 0.3, got {init_nse:.3f}")

        # A2: Initial Low_Flow_Bias should be < -0.3
        lfb = init_metrics.get('Low_Flow_Bias', 0.0)
        self.assertLess(lfb, -0.3,
                        f"Initial Low_Flow_Bias should be < -0.3, got {lfb:.3f}")

        # A3: LinearReservoir(slow_gw) should appear in some iteration
        has_slowgw = False
        for entry in agent.history:
            layer_ids = {l['id'] for l in entry['structure'].get('layers', [])}
            if 'slow_gw' in layer_ids:
                has_slowgw = True
                break
        self.assertTrue(has_slowgw,
                        "LinearReservoir(slow_gw) should be inserted within 3 iterations")

        # A4: NSE should improve
        self.assertGreater(result['best_nse'], init_nse,
                           f"best_nse ({result['best_nse']:.3f}) should improve over "
                           f"initial ({init_nse:.3f})")


if __name__ == '__main__':
    unittest.main()
