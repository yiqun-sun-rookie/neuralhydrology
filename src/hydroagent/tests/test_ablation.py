"""Tests for ablation support: metric group filtering, RandomLLMClient, and batch smoke.

Run:  python -m pytest src/hydroagent/tests/test_ablation.py -v
"""
import json
import os
import sys
import unittest

import numpy as np
import pandas as pd

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))

from hydroagent.diagnosis import HydroDiagnostician, METRIC_GROUPS, _METRIC_TO_GROUP
from hydroagent.agent import RandomLLMClient, MockLLMClient, SYSTEM_PROMPT, build_refinement_prompt, DEFAULT_INITIAL_STRUCTURE


def _make_synthetic_data(n=365, seed=42):
    """Create synthetic obs/sim with DatetimeIndex for testing."""
    rng = np.random.RandomState(seed)
    dates = pd.date_range('2000-01-01', periods=n, freq='D')
    obs = np.abs(np.sin(np.arange(n) * 2 * np.pi / 365) * 5 + rng.randn(n) * 0.5 + 3)
    sim = obs * 0.9 + rng.randn(n) * 0.3 + 0.5
    sim = np.maximum(sim, 0.01)
    return pd.Series(obs, index=dates), pd.Series(sim, index=dates)


class TestMetricGroupConstants(unittest.TestCase):
    """Verify METRIC_GROUPS and _METRIC_TO_GROUP are consistent."""

    def test_all_metrics_mapped(self):
        all_metrics = set()
        for ms in METRIC_GROUPS.values():
            all_metrics.update(ms)
        for m in all_metrics:
            self.assertIn(m, _METRIC_TO_GROUP)

    def test_reverse_map_points_to_group(self):
        for m, g in _METRIC_TO_GROUP.items():
            self.assertIn(g, METRIC_GROUPS)
            self.assertIn(m, METRIC_GROUPS[g])


class TestDiagnosticianGroups(unittest.TestCase):
    """Test enabled_groups filtering logic in HydroDiagnostician."""

    def test_default_returns_all_metrics(self):
        obs, sim = _make_synthetic_data()
        doc = HydroDiagnostician()
        report = doc.generate_report(obs, sim)
        metrics = report['metrics']
        # Should contain metrics from all groups
        for group, metric_names in METRIC_GROUPS.items():
            for m in metric_names:
                self.assertIn(m, metrics, f"Missing {m} from group {group}")

    def test_enabled_groups_filters_metrics(self):
        obs, sim = _make_synthetic_data()
        doc = HydroDiagnostician(enabled_groups=['hydro_basic'])
        report = doc.generate_report(obs, sim)
        metrics = report['metrics']
        # Should only have hydro_basic metrics
        for m in metrics:
            group = _METRIC_TO_GROUP.get(m, 'hydro_basic')
            self.assertEqual(group, 'hydro_basic', f"Metric {m} should be filtered out")

    def test_empty_enabled_groups_returns_empty_metrics(self):
        obs, sim = _make_synthetic_data()
        doc = HydroDiagnostician(enabled_groups=[])
        report = doc.generate_report(obs, sim)
        self.assertEqual(len(report['metrics']), 0)
        # Feedback should be empty too (no metrics to trigger rules)
        self.assertEqual(len(report['semantic_feedback']), 0)

    def test_multiple_groups(self):
        obs, sim = _make_synthetic_data()
        groups = ['hydro_basic', 'seasonal']
        doc = HydroDiagnostician(enabled_groups=groups)
        report = doc.generate_report(obs, sim)
        metrics = report['metrics']
        allowed = set()
        for g in groups:
            allowed.update(METRIC_GROUPS[g])
        for m in metrics:
            self.assertIn(m, allowed, f"Metric {m} not in allowed groups")

    def test_none_enabled_groups_means_all(self):
        obs, sim = _make_synthetic_data()
        doc = HydroDiagnostician(enabled_groups=None)
        report = doc.generate_report(obs, sim)
        # Same as default
        all_metrics = set()
        for ms in METRIC_GROUPS.values():
            all_metrics.update(ms)
        for m in all_metrics:
            self.assertIn(m, report['metrics'])


class TestRandomLLMClient(unittest.TestCase):
    """Test RandomLLMClient produces valid JSON structures."""

    def test_output_is_valid_json(self):
        client = RandomLLMClient(seed=42)
        report = {'metrics': {'NSE': 0.3}, 'semantic_feedback': []}
        prompt = build_refinement_prompt(DEFAULT_INITIAL_STRUCTURE, report, 1, 0.6)
        response = client.chat(SYSTEM_PROMPT, prompt)
        result = json.loads(response)
        self.assertIn('layers', result)
        self.assertIn('model_name', result)
        self.assertTrue(result['model_name'].startswith('random_'))

    def test_deterministic_with_same_seed(self):
        c1 = RandomLLMClient(seed=123)
        c2 = RandomLLMClient(seed=123)
        report = {'metrics': {'NSE': 0.3}, 'semantic_feedback': []}
        prompt = build_refinement_prompt(DEFAULT_INITIAL_STRUCTURE, report, 1, 0.6)
        r1 = c1.chat(SYSTEM_PROMPT, prompt)
        r2 = c2.chat(SYSTEM_PROMPT, prompt)
        self.assertEqual(r1, r2)

    def test_different_seeds_differ(self):
        c1 = RandomLLMClient(seed=1)
        c2 = RandomLLMClient(seed=99)
        report = {'metrics': {'NSE': 0.3}, 'semantic_feedback': []}
        prompt = build_refinement_prompt(DEFAULT_INITIAL_STRUCTURE, report, 1, 0.6)
        r1 = c1.chat(SYSTEM_PROMPT, prompt)
        r2 = c2.chat(SYSTEM_PROMPT, prompt)
        # Very likely different (not guaranteed but with these seeds they should be)
        self.assertNotEqual(r1, r2)

    def test_multiple_iterations_valid(self):
        client = RandomLLMClient(seed=42)
        structure = DEFAULT_INITIAL_STRUCTURE.copy()
        for i in range(5):
            report = {'metrics': {'NSE': 0.3}, 'semantic_feedback': []}
            prompt = build_refinement_prompt(structure, report, i + 1, 0.6)
            response = client.chat(SYSTEM_PROMPT, prompt)
            structure = json.loads(response)
            self.assertIn('layers', structure)
            self.assertGreater(len(structure['layers']), 0)


if __name__ == '__main__':
    unittest.main()
