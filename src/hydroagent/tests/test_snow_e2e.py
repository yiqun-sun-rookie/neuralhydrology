"""End-to-end integration test for HydroAgent SnowReservoir signal chain.

Verifies the full pipeline:
  snow-model-generated obs (inverse crime)
  -> initial model overestimates winter flow (Winter_Bias > +0.3)
  -> MockLLM inserts SnowReservoir (rewires soil input)
  -> SuperflexEnv calibrates -> NSE improves significantly
"""

import unittest
import sys
import os

import numpy as np
import pandas as pd

# Add src root so `import hydroagent` works after package migration
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))

try:
    from hydroagent.agent import HydroAgent, MockLLMClient, DEFAULT_INITIAL_STRUCTURE
    from hydroagent.environment import SuperflexEnv
except ImportError:
    sys.path.append(os.getcwd())
    from hydroagent.agent import HydroAgent, MockLLMClient, DEFAULT_INITIAL_STRUCTURE
    from hydroagent.environment import SuperflexEnv


# ---------------------------------------------------------------------------
# Synthetic data generators
# ---------------------------------------------------------------------------

_SNOW_STRUCTURE = {
    'model_name': 'truth_snow',
    'layers': [
        {'id': 'snow', 'type': 'SnowReservoir',
         'inputs': ['prcp', 'temperature'], 'parameters': ['t0', 'k', 'm']},
        {'id': 'soil', 'type': 'UnsaturatedReservoir',
         'inputs': ['snow.outflow', 'ep'], 'parameters': ['Smax', 'Ce', 'm', 'beta']},
        {'id': 'fast', 'type': 'PowerReservoir',
         'inputs': ['soil.runoff'], 'parameters': ['k', 'alpha']},
    ],
    'lag_functions': [],
    'system_output': ['fast'],
}


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


def _make_snow_obs(forcing, rng):
    """Generate obs by running the snow model with default params (inverse crime).

    Physics: SnowReservoir stores winter precipitation as snow,
    releasing it as melt in spring. Without a snow component, a model
    will overestimate winter flow (Winter_Bias > +0.3).
    """
    env = SuperflexEnv()
    env.parse_structure(_SNOW_STRUCTURE)
    obs = env.run_simulation(forcing)
    obs = obs + rng.normal(0, 0.05, len(obs))
    return obs.clip(lower=0.01)


def _make_uniform_data(n_days=730, seed=123):
    """Create forcing/obs with NO seasonal bias (constant EP, warm temperature).

    Constant EP eliminates the winter-low-evaporation effect that causes
    the model to overestimate winter flow and trigger the snow rule.
    """
    rng = np.random.RandomState(seed)
    dates = pd.date_range('2000-01-01', periods=n_days, freq='D')

    tmean = 15.0 + rng.normal(0, 2, n_days)  # warm, no seasonality
    prcp = rng.exponential(3.0, n_days)
    ep = np.full(n_days, 2.5)  # constant, no seasonality

    forcing = pd.DataFrame({'prcp': prcp, 'ep': ep, 'tmean': tmean}, index=dates)
    obs_arr = np.maximum(prcp * 0.3 + rng.normal(0, 0.2, n_days), 0.05)
    return forcing, pd.Series(obs_arr, index=dates)


# ---------------------------------------------------------------------------
# Test class
# ---------------------------------------------------------------------------

class TestSnowE2E(unittest.TestCase):
    """End-to-end: diagnosis -> decision -> modelling -> calibration."""

    _orig_calibrate = None

    def setUp(self):
        TestSnowE2E._orig_calibrate = SuperflexEnv._calibrate_sfpy

        def _fast_calibrate(self_env, forcing, obs, n_trials=50):
            return TestSnowE2E._orig_calibrate(self_env, forcing, obs, n_trials=50)

        SuperflexEnv._calibrate_sfpy = _fast_calibrate

    def tearDown(self):
        if TestSnowE2E._orig_calibrate is not None:
            SuperflexEnv._calibrate_sfpy = TestSnowE2E._orig_calibrate

    # ---------------------------------------------------------------
    # Test 1: core end-to-end — NSE must improve
    # ---------------------------------------------------------------
    def test_solve_inserts_snow_reservoir(self):
        """Snow-generated obs -> Winter_Bias > +0.3 -> add SnowReservoir -> NSE improves."""
        forcing, rng = _make_forcing()
        obs = _make_snow_obs(forcing, rng)

        agent = HydroAgent(
            llm_client=MockLLMClient(),
            max_iterations=3,
        )
        result = agent.solve(forcing, obs, target_nse=0.99)

        # -- A1: Winter_Bias > +0.3 detected in iteration 1 --
        iter1 = agent.history[0]
        wb = iter1['report']['metrics'].get('Winter_Bias', 0.0)
        self.assertGreater(wb, 0.3,
                           f"Iteration 1 Winter_Bias should be > +0.3, got {wb:.3f}")

        # -- A2: SnowReservoir appears in some iteration --
        snow_structure = None
        for entry in agent.history:
            layer_types = {l['type'] for l in entry['structure'].get('layers', [])}
            if 'SnowReservoir' in layer_types:
                snow_structure = entry['structure']
                break
        self.assertIsNotNone(snow_structure, "SnowReservoir should be inserted within 3 iterations")

        # -- A3: soil layer rewired to snow.outflow --
        soil_layers = [l for l in snow_structure['layers']
                       if l['type'] == 'UnsaturatedReservoir']
        if soil_layers:
            soil_inputs = soil_layers[0].get('inputs', [])
            self.assertTrue(
                any('snow.outflow' in inp for inp in soil_inputs),
                f"Soil inputs should contain 'snow.outflow', got {soil_inputs}")

        # -- A4: SnowReservoir structure achieves good NSE --
        snow_entries = [e for e in agent.history
                        if 'SnowReservoir' in {l['type'] for l in e['structure'].get('layers', [])}]
        snow_nse = snow_entries[0]['nse']
        self.assertGreater(snow_nse, 0.5,
                           f"Snow structure should achieve NSE > 0.5, got {snow_nse:.3f}")

        # -- A5: NSE improved over initial --
        init_nse = agent.history[0]['nse']
        self.assertGreater(result['best_nse'], init_nse + 0.1,
                           f"best_nse ({result['best_nse']:.3f}) should improve over "
                           f"initial ({init_nse:.3f}) by at least 0.1")

    # ---------------------------------------------------------------
    # Test 2: hybrid topology calibrates correctly (inverse crime)
    # ---------------------------------------------------------------
    def test_snow_structure_calibrates(self):
        """Snow structure calibrates well against its own output (topology check)."""
        forcing, rng = _make_forcing()

        env = SuperflexEnv()
        env.parse_structure(_SNOW_STRUCTURE)
        obs = env.run_simulation(forcing)
        obs = (obs + np.random.RandomState(99).normal(0, 0.05, len(obs))).clip(lower=0.01)

        result = env.auto_calibrate(forcing, obs)
        self.assertGreater(result['nse'], 0.5,
                           f"Snow structure should fit its own output, got NSE={result['nse']:.3f}")

    # ---------------------------------------------------------------
    # Test 3: negative control
    # ---------------------------------------------------------------
    def test_no_snow_without_winter_bias(self):
        """Uniform data -> no winter overestimate -> no SnowReservoir."""
        forcing, obs = _make_uniform_data()

        agent = HydroAgent(
            llm_client=MockLLMClient(),
            max_iterations=3,
        )
        result = agent.solve(forcing, obs, target_nse=0.99)

        self.assertGreater(result['best_nse'], -999.0)

        for entry in agent.history:
            layer_types = {l['type'] for l in entry['structure'].get('layers', [])}
            self.assertNotIn(
                'SnowReservoir', layer_types,
                f"SnowReservoir should NOT appear without winter bias "
                f"(iteration {entry['iteration']})")


if __name__ == '__main__':
    unittest.main()
