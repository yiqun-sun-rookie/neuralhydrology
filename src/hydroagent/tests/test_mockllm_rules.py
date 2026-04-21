"""Unit tests for all 7 MockLLM rules — positive triggers and guard conditions.

Each test constructs a prompt via build_refinement_prompt() with specific metric
values, calls MockLLMClient.chat(), and verifies the output JSON structure.
"""

import json
import os
import sys
import unittest
from copy import deepcopy

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))

from hydroagent.agent import (
    MockLLMClient,
    SYSTEM_PROMPT,
    DEFAULT_INITIAL_STRUCTURE,
    build_refinement_prompt,
)


def _make_report(metrics_overrides: dict) -> dict:
    """Build a minimal diagnostic report with default-safe metrics, then override."""
    defaults = {
        'NSE': 0.5,
        'Peak_Lag_Hours': 1.0,
        'Low_Flow_Bias': 0.0,
        'Recession_K_Ratio': 1.0,
        'High_Freq_Energy_Ratio': 1.0,
        'Winter_Bias': 0.1,
    }
    defaults.update(metrics_overrides)
    return {'metrics': defaults, 'semantic_feedback': []}


def _call_mock(structure: dict, report: dict) -> dict:
    """Helper: build prompt, call MockLLM, parse JSON response."""
    prompt = build_refinement_prompt(structure, report, iteration=1, target_nse=0.9)
    response = MockLLMClient().chat(SYSTEM_PROMPT, prompt)
    return json.loads(response)


class TestRule1AddBaseflow(unittest.TestCase):
    """Rule 1: NSE < 0.3 → add RoutingStore(baseflow)."""

    def test_rule1_add_baseflow(self):
        report = _make_report({'NSE': 0.2})
        result = _call_mock(deepcopy(DEFAULT_INITIAL_STRUCTURE), report)

        layer_ids = {l['id'] for l in result['layers']}
        layer_types = {l['type'] for l in result['layers']}
        self.assertIn('baseflow', layer_ids)
        self.assertIn('RoutingStore', layer_types)
        self.assertIn('baseflow', result.get('system_output', []))
        self.assertIn('add_baseflow', result['model_name'])

    def test_rule1_guard_baseflow_exists(self):
        structure = deepcopy(DEFAULT_INITIAL_STRUCTURE)
        structure['layers'].append({
            'id': 'baseflow', 'type': 'RoutingStore',
            'parameters': ['x2', 'x3', 'gamma', 'omega'],
            'inputs': ['soil.runoff'],
        })
        structure['system_output'] = ['fast', 'baseflow']
        report = _make_report({'NSE': 0.2})
        result = _call_mock(structure, report)

        # baseflow already exists → Rule 1 blocked (lower-priority rules may fire)
        self.assertNotIn('add_baseflow', result['model_name'])
        baseflow_count = sum(1 for l in result['layers'] if l['id'] == 'baseflow')
        self.assertEqual(baseflow_count, 1, "Should not duplicate baseflow")


class TestRule2RemoveLag(unittest.TestCase):
    """Rule 2: Peak_Lag > 3.0 and lag_functions non-empty → clear lag_functions."""

    def test_rule2_remove_lag(self):
        structure = deepcopy(DEFAULT_INITIAL_STRUCTURE)
        structure['lag_functions'] = [
            {'type': 'HalfTriangularLag', 'target': 'fast', 'lag_steps': 5}
        ]
        report = _make_report({'NSE': 0.5, 'Peak_Lag_Hours': 5.0})
        result = _call_mock(structure, report)

        self.assertEqual(result['lag_functions'], [])
        self.assertIn('remove_lag', result['model_name'])

    def test_rule2_guard_no_lag(self):
        structure = deepcopy(DEFAULT_INITIAL_STRUCTURE)
        structure['lag_functions'] = []
        report = _make_report({'NSE': 0.5, 'Peak_Lag_Hours': 5.0})
        result = _call_mock(structure, report)

        # lag_functions already empty → Rule 2 blocked → no_change
        self.assertIn('no_change', result['model_name'])


class TestRule3AddSnow(unittest.TestCase):
    """Rule 3: Winter_Bias > 0.3 → add SnowReservoir."""

    def test_rule3_add_snow(self):
        report = _make_report({'NSE': 0.5, 'Winter_Bias': 0.5})
        result = _call_mock(deepcopy(DEFAULT_INITIAL_STRUCTURE), report)

        layer_types = {l['type'] for l in result['layers']}
        self.assertIn('SnowReservoir', layer_types)
        self.assertIn('add_snow', result['model_name'])

        # Verify soil was rewired
        soil_layers = [l for l in result['layers'] if l['type'] == 'UnsaturatedReservoir']
        if soil_layers:
            self.assertIn('snow.outflow', soil_layers[0]['inputs'])

    def test_rule3_guard_snow_exists(self):
        structure = deepcopy(DEFAULT_INITIAL_STRUCTURE)
        structure['layers'].insert(0, {
            'id': 'snow', 'type': 'SnowReservoir',
            'parameters': ['t0', 'k', 'm'], 'inputs': ['prcp', 'temperature'],
        })
        report = _make_report({'NSE': 0.5, 'Winter_Bias': 0.5})
        result = _call_mock(structure, report)

        # SnowReservoir already exists → Rule 3 blocked → no_change
        self.assertIn('no_change', result['model_name'])


class TestRule4AddSlowGW(unittest.TestCase):
    """Rule 4: Low_Flow_Bias < -0.3 → add LinearReservoir(slow_gw)."""

    def test_rule4_add_slow_gw(self):
        report = _make_report({'NSE': 0.5, 'Low_Flow_Bias': -0.4})
        result = _call_mock(deepcopy(DEFAULT_INITIAL_STRUCTURE), report)

        layer_ids = {l['id'] for l in result['layers']}
        self.assertIn('slow_gw', layer_ids)
        slow_gw = [l for l in result['layers'] if l['id'] == 'slow_gw'][0]
        self.assertEqual(slow_gw['type'], 'LinearReservoir')
        self.assertIn('slow_gw', result.get('system_output', []))
        self.assertIn('add_slow_gw', result['model_name'])

    def test_rule4_guard_slow_gw_exists(self):
        structure = deepcopy(DEFAULT_INITIAL_STRUCTURE)
        structure['layers'].append({
            'id': 'slow_gw', 'type': 'LinearReservoir',
            'parameters': ['k'], 'inputs': ['soil.runoff'],
        })
        structure['system_output'] = ['fast', 'slow_gw']
        report = _make_report({'NSE': 0.5, 'Low_Flow_Bias': -0.4})
        result = _call_mock(structure, report)

        # slow_gw already exists → Rule 4 blocked → no_change
        self.assertIn('no_change', result['model_name'])


class TestRule5AddSlowReservoir(unittest.TestCase):
    """Rule 5: Recession_K_Ratio > 1.3 → add LinearReservoir(slow_reservoir)."""

    def test_rule5_add_slow_reservoir(self):
        report = _make_report({'NSE': 0.5, 'Recession_K_Ratio': 1.5})
        result = _call_mock(deepcopy(DEFAULT_INITIAL_STRUCTURE), report)

        layer_ids = {l['id'] for l in result['layers']}
        self.assertIn('slow_reservoir', layer_ids)
        slow_res = [l for l in result['layers'] if l['id'] == 'slow_reservoir'][0]
        self.assertEqual(slow_res['type'], 'LinearReservoir')
        self.assertIn('slow_reservoir', result.get('system_output', []))
        self.assertIn('add_slow_res', result['model_name'])

    def test_rule5_guard_exists(self):
        structure = deepcopy(DEFAULT_INITIAL_STRUCTURE)
        structure['layers'].append({
            'id': 'slow_reservoir', 'type': 'LinearReservoir',
            'parameters': ['k'], 'inputs': ['soil.runoff'],
        })
        structure['system_output'] = ['fast', 'slow_reservoir']
        report = _make_report({'NSE': 0.5, 'Recession_K_Ratio': 1.5})
        result = _call_mock(structure, report)

        # slow_reservoir already exists → Rule 5 blocked → no_change
        self.assertIn('no_change', result['model_name'])


class TestRule6LinearToPower(unittest.TestCase):
    """Rule 6: Energy_Ratio < 0.6 → replace LinearReservoir with PowerReservoir."""

    def test_rule6_linear_to_power(self):
        structure = deepcopy(DEFAULT_INITIAL_STRUCTURE)
        structure['layers'].append({
            'id': 'slow', 'type': 'LinearReservoir',
            'parameters': ['k'], 'inputs': ['soil.runoff'],
        })
        structure['system_output'] = ['fast', 'slow']
        report = _make_report({'NSE': 0.5, 'High_Freq_Energy_Ratio': 0.4})
        result = _call_mock(structure, report)

        slow_layers = [l for l in result['layers'] if l['id'] == 'slow']
        self.assertEqual(len(slow_layers), 1)
        self.assertEqual(slow_layers[0]['type'], 'PowerReservoir')
        self.assertEqual(slow_layers[0]['parameters'], ['k', 'alpha'])
        self.assertIn('linear_to_power', result['model_name'])

    def test_rule6_guard_no_linear(self):
        # DEFAULT structure has no LinearReservoir
        report = _make_report({'NSE': 0.5, 'High_Freq_Energy_Ratio': 0.4})
        result = _call_mock(deepcopy(DEFAULT_INITIAL_STRUCTURE), report)

        # No LinearReservoir to replace → no_change
        self.assertIn('no_change', result['model_name'])


class TestRule7UnsaturatedToProduction(unittest.TestCase):
    """Rule 7: NSE < 0.5 → replace UnsaturatedReservoir with ProductionStore."""

    def test_rule7_to_production(self):
        # NSE=0.4, all other metrics normal (no higher-priority rule triggers)
        report = _make_report({'NSE': 0.4, 'High_Freq_Energy_Ratio': 0.8})
        result = _call_mock(deepcopy(DEFAULT_INITIAL_STRUCTURE), report)

        layer_types = {l['type'] for l in result['layers']}
        self.assertIn('ProductionStore', layer_types)
        self.assertNotIn('UnsaturatedReservoir', layer_types)

        prod = [l for l in result['layers'] if l['type'] == 'ProductionStore'][0]
        self.assertEqual(prod['parameters'], ['x1', 'alpha', 'beta', 'ni'])
        self.assertEqual(prod['inputs'], ['ep', 'prcp'])
        self.assertIn('try_production_store', result['model_name'])

    def test_rule7_guard_production_exists(self):
        structure = deepcopy(DEFAULT_INITIAL_STRUCTURE)
        # Replace soil with ProductionStore
        structure['layers'][0] = {
            'id': 'soil', 'type': 'ProductionStore',
            'parameters': ['x1', 'alpha', 'beta', 'ni'],
            'inputs': ['ep', 'prcp'],
        }
        report = _make_report({'NSE': 0.4, 'High_Freq_Energy_Ratio': 0.8})
        result = _call_mock(structure, report)

        # ProductionStore already exists → Rule 7 blocked → no_change
        self.assertIn('no_change', result['model_name'])


if __name__ == '__main__':
    unittest.main()
