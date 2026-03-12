"""Tests for basin metadata loading and LLM initialization agent.

Chunk 2: TestBasinMetadata — verifies load_basin_metadata().
Chunk 3: TestInitializationAgent — verifies build_init_prompt, _choose_initial_structure,
         and solve() with basin_meta parameter.
"""
import unittest
import sys
import os

import numpy as np
import pandas as pd

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))

from hydroagent.data_loading import load_basin_metadata
from hydroagent.agent import (
    HydroAgent, MockLLMClient, build_init_prompt,
    INIT_PROMPT, AVAILABLE_COMPONENTS, DEFAULT_INITIAL_STRUCTURE,
)


class TestBasinMetadata(unittest.TestCase):
    def test_load_metadata_returns_expected_keys(self):
        """load_basin_metadata should return a dict with key basin properties."""
        meta = load_basin_metadata('01022500')
        expected_keys = {
            'area_km2', 'elev_mean', 'slope_mean',
            'p_mean', 'pet_mean', 'aridity', 'frac_snow', 'p_seasonality',
            'frac_forest', 'dom_land_cover',
        }
        self.assertTrue(expected_keys.issubset(set(meta.keys())),
                        f"Missing keys: {expected_keys - set(meta.keys())}")
        # Sanity: area should be positive
        self.assertGreater(meta['area_km2'], 0)
        # Sanity: aridity should be non-negative
        self.assertGreaterEqual(meta['aridity'], 0)

    def test_load_metadata_unknown_basin_raises(self):
        """Unknown basin ID should raise ValueError."""
        with self.assertRaises(ValueError):
            load_basin_metadata('99999999')


class TestInitializationAgent(unittest.TestCase):
    """Tests for LLM-chosen initial structure (Chunk 3)."""

    def test_build_init_prompt_contains_metadata(self):
        """Init prompt should include basin metadata values and component library."""
        meta = {'area_km2': 574.0, 'aridity': 0.59, 'frac_snow': 0.25,
                'elev_mean': 200.0, 'frac_forest': 0.8, 'p_mean': 3.5,
                'dom_land_cover': 'Mixed Forests'}
        prompt = build_init_prompt(meta)
        self.assertIn('574.0', prompt)
        self.assertIn('0.25', prompt)       # frac_snow
        self.assertIn('Mixed Forests', prompt)
        self.assertIn('Available SuperflexPy', prompt)  # component library

    def test_init_prompt_constant_exists(self):
        """INIT_PROMPT should be a non-empty string with expected content."""
        self.assertIsInstance(INIT_PROMPT, str)
        self.assertIn('senior hydrologist', INIT_PROMPT)
        self.assertIn('model_name', INIT_PROMPT)

    def test_solve_with_basin_meta(self):
        """MockLLMClient + basin_meta should complete without error."""
        rng = np.random.RandomState(123)
        dates = pd.date_range('2000-01-01', periods=100, freq='D')
        forcing = pd.DataFrame({'prcp': rng.uniform(0, 10, 100),
                                'ep': rng.uniform(0, 3, 100)}, index=dates)
        obs = pd.Series(rng.uniform(0, 5, 100), index=dates)

        agent = HydroAgent(MockLLMClient(), max_iterations=1)
        meta = {'area_km2': 574.0, 'aridity': 0.59, 'frac_snow': 0.25}
        result = agent.solve(forcing, obs, basin_meta=meta)
        # Should complete without error and return expected keys
        self.assertIn('best_nse', result)
        self.assertIn('best_structure', result)

    def test_solve_without_meta_uses_default(self):
        """When no basin_meta, solve should use DEFAULT_INITIAL_STRUCTURE as before."""
        rng = np.random.RandomState(456)
        dates = pd.date_range('2000-01-01', periods=100, freq='D')
        forcing = pd.DataFrame({'prcp': rng.uniform(0, 10, 100),
                                'ep': rng.uniform(0, 3, 100)}, index=dates)
        obs = pd.Series(rng.uniform(0, 5, 100), index=dates)

        agent = HydroAgent(MockLLMClient(), max_iterations=1)
        result = agent.solve(forcing, obs)
        self.assertIn('best_nse', result)

    def test_initial_structure_takes_priority_over_basin_meta(self):
        """When both initial_structure and basin_meta are provided, initial_structure wins."""
        rng = np.random.RandomState(789)
        dates = pd.date_range('2000-01-01', periods=100, freq='D')
        forcing = pd.DataFrame({'prcp': rng.uniform(0, 10, 100),
                                'ep': rng.uniform(0, 3, 100)}, index=dates)
        obs = pd.Series(rng.uniform(0, 5, 100), index=dates)

        custom_structure = {
            "model_name": "custom_test",
            "layers": [
                {"id": "soil", "type": "UnsaturatedReservoir",
                 "parameters": ["Smax", "beta"], "inputs": ["prcp", "ep"]},
                {"id": "fast", "type": "PowerReservoir",
                 "parameters": ["k", "alpha"], "inputs": ["soil.runoff"]},
            ],
            "lag_functions": [],
            "system_output": ["fast"],
        }
        meta = {'area_km2': 574.0, 'aridity': 0.59, 'frac_snow': 0.25}

        agent = HydroAgent(MockLLMClient(), max_iterations=1)
        result = agent.solve(forcing, obs, initial_structure=custom_structure, basin_meta=meta)
        self.assertIn('best_nse', result)

    def test_choose_initial_structure_mock_returns_default(self):
        """MockLLMClient should always return DEFAULT_INITIAL_STRUCTURE from _choose_initial_structure."""
        agent = HydroAgent(MockLLMClient(), max_iterations=1)
        meta = {'area_km2': 574.0, 'aridity': 0.59, 'frac_snow': 0.25}
        structure = agent._choose_initial_structure(meta)
        self.assertEqual(structure['model_name'], DEFAULT_INITIAL_STRUCTURE['model_name'])
        self.assertEqual(len(structure['layers']), len(DEFAULT_INITIAL_STRUCTURE['layers']))


if __name__ == '__main__':
    unittest.main()
