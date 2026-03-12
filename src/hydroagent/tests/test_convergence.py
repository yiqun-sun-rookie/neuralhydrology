"""Tests for convergence control in HydroAgent.solve().

Verifies that:
1. Floor protection stops hopeless basins early (best_nse < floor_nse after floor_patience).
2. The old target_nse early-stop is gone: agent runs all max_iterations even when NSE > 0.6.
3. floor_nse / floor_patience parameters are respected.
"""

import os
import sys
import unittest

import numpy as np
import pandas as pd

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))

from hydroagent.agent import HydroAgent, MockLLMClient


class TestFloorProtection(unittest.TestCase):
    """Floor protection should stop early when the basin is hopeless."""

    def test_floor_stops_adversarial_data(self):
        """With zero forcing and constant obs=100, NSE is deeply negative.
        Floor protection (floor_nse=0.0, floor_patience=2) should stop after 2 iterations."""
        dates = pd.date_range('2000-01-01', periods=100, freq='D')
        forcing = pd.DataFrame({'prcp': np.zeros(100), 'ep': np.zeros(100)}, index=dates)
        obs = pd.Series(np.ones(100) * 100.0, index=dates)

        agent = HydroAgent(MockLLMClient(), max_iterations=4)
        result = agent.solve(forcing, obs, floor_nse=0.0, floor_patience=2)

        # best_nse should be negative (model can't produce 100 from zero forcing)
        self.assertLess(result['best_nse'], 0.0)
        # Should stop after floor_patience=2 iterations, not run all 4
        self.assertLessEqual(len(agent.history), 2)

    def test_floor_patience_respected(self):
        """With floor_patience=3, agent should run at least 3 iterations even with bad data."""
        dates = pd.date_range('2000-01-01', periods=100, freq='D')
        forcing = pd.DataFrame({'prcp': np.zeros(100), 'ep': np.zeros(100)}, index=dates)
        obs = pd.Series(np.ones(100) * 100.0, index=dates)

        agent = HydroAgent(MockLLMClient(), max_iterations=5)
        result = agent.solve(forcing, obs, floor_nse=0.0, floor_patience=3)

        # Should not stop before floor_patience=3
        self.assertGreaterEqual(len(agent.history), 3)
        # But should stop at 3, not run all 5
        self.assertLessEqual(len(agent.history), 3)

    def test_floor_disabled_with_very_low_floor(self):
        """With floor_nse=-999, floor protection never triggers."""
        dates = pd.date_range('2000-01-01', periods=100, freq='D')
        forcing = pd.DataFrame({'prcp': np.zeros(100), 'ep': np.zeros(100)}, index=dates)
        obs = pd.Series(np.ones(100) * 100.0, index=dates)

        agent = HydroAgent(MockLLMClient(), max_iterations=3)
        result = agent.solve(forcing, obs, floor_nse=-999.0, floor_patience=2)

        # Should run all 3 iterations since floor_nse is impossibly low
        self.assertEqual(len(agent.history), 3)


class TestNoTargetNseEarlyStop(unittest.TestCase):
    """The old target_nse >= 0.6 early-stop must NOT trigger."""

    def test_runs_all_iterations_regardless_of_nse(self):
        """solve() should run all max_iterations even when NSE exceeds target_nse.

        We use a fixed seed to get reproducible data, and set floor_nse=-999
        to ensure floor protection doesn't interfere. The key check: all
        max_iterations are executed, regardless of the NSE value.
        """
        rng = np.random.RandomState(42)
        dates = pd.date_range('2000-01-01', periods=200, freq='D')
        prcp = rng.uniform(0, 10, 200)
        forcing = pd.DataFrame({
            'prcp': prcp,
            'ep': prcp * 0.3,
        }, index=dates)
        obs = pd.Series(prcp * 0.4 + rng.normal(0, 0.3, 200).clip(0), index=dates)

        max_iter = 3
        agent = HydroAgent(MockLLMClient(), max_iterations=max_iter)
        result = agent.solve(forcing, obs, target_nse=0.6, floor_nse=-999.0, floor_patience=2)

        # Must run all iterations - target_nse should NOT cause early stopping
        self.assertEqual(len(agent.history), max_iter)

    def test_target_nse_still_in_signature(self):
        """target_nse parameter should still be accepted for backward compatibility."""
        dates = pd.date_range('2000-01-01', periods=100, freq='D')
        forcing = pd.DataFrame({
            'prcp': np.random.uniform(0, 10, 100),
            'ep': np.random.uniform(0, 3, 100),
        }, index=dates)
        obs = pd.Series(np.random.uniform(0, 5, 100), index=dates)

        agent = HydroAgent(MockLLMClient(), max_iterations=1)
        # Should not raise TypeError
        result = agent.solve(forcing, obs, target_nse=0.9)
        self.assertIn('best_nse', result)


class TestFloorAndMaxInteraction(unittest.TestCase):
    """Test interaction between floor_patience and max_iterations."""

    def test_max_iterations_wins_when_floor_patience_exceeds_max(self):
        """If floor_patience > max_iterations, floor check never triggers."""
        dates = pd.date_range('2000-01-01', periods=100, freq='D')
        forcing = pd.DataFrame({'prcp': np.zeros(100), 'ep': np.zeros(100)}, index=dates)
        obs = pd.Series(np.ones(100) * 100.0, index=dates)

        agent = HydroAgent(MockLLMClient(), max_iterations=2)
        result = agent.solve(forcing, obs, floor_nse=0.0, floor_patience=5)

        # floor_patience=5 > max_iterations=2, so floor check never applies
        # Agent runs all 2 iterations and stops at max
        self.assertEqual(len(agent.history), 2)

    def test_default_parameters(self):
        """Default floor_nse=0.0 and floor_patience=2 should work without explicit args."""
        dates = pd.date_range('2000-01-01', periods=100, freq='D')
        forcing = pd.DataFrame({'prcp': np.zeros(100), 'ep': np.zeros(100)}, index=dates)
        obs = pd.Series(np.ones(100) * 100.0, index=dates)

        agent = HydroAgent(MockLLMClient(), max_iterations=4)
        # Use defaults: floor_nse=0.0, floor_patience=2
        result = agent.solve(forcing, obs)

        # With adversarial data and default floor settings, should stop at iteration 2
        self.assertLessEqual(len(agent.history), 2)


if __name__ == '__main__':
    unittest.main()
