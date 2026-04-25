"""Regression tests for the xaj_global_pilot repro_v01 benchmark-aligned protocol.

These tests verify protocol scaffolding without running real calibrations:
- repro_split_periods exposes only calibration / evaluation
- v02 split_periods is unchanged
- run_single_model_basin rejects unknown protocols
- run_single_model_basin labels result rows with the right period name
- SuperflexEnv._calibrate_sfpy honours n_restarts (CMA-ES called N times,
  with the agreed-upon seed schedule)

The SuperflexEnv suite is skipped if superflexpy is not importable in the
current environment (HPC has it; local dev typically does not until
external/superflexpy is populated).
"""
import os
import sys
import unittest
from unittest.mock import MagicMock, patch

import numpy as np
import pandas as pd

_HERE = os.path.dirname(__file__)
_REPO_ROOT = os.path.abspath(os.path.join(_HERE, '..'))
_SRC_ROOT = os.path.join(_REPO_ROOT, 'src')
for _p in (_REPO_ROOT, _SRC_ROOT):
    if _p not in sys.path:
        sys.path.insert(0, _p)

from src.xaj_global_pilot.config import repro_split_periods, split_periods

# SuperflexEnv pulls in superflexpy; that dependency is bundled under
# external/superflexpy on HPC but may be absent in local dev. Tests that
# need it are skipped if the import fails.
try:
    from hydroagent.environment import SuperflexEnv  # noqa: F401
    _HAS_SUPERFLEX = True
except Exception:  # ImportError, ModuleNotFoundError, or anything raised by environment.py imports
    _HAS_SUPERFLEX = False


class TestProtocolSegments(unittest.TestCase):
    def test_repro_has_only_calibration_and_evaluation(self):
        periods = repro_split_periods()
        self.assertEqual(list(periods.keys()), ['calibration', 'evaluation'])
        self.assertNotIn('validation', periods)
        self.assertNotIn('train', periods)
        self.assertNotIn('test', periods)

    def test_v02_split_periods_unchanged(self):
        periods = split_periods()
        self.assertEqual(list(periods.keys()), ['train', 'validation', 'test'])


@unittest.skipUnless(_HAS_SUPERFLEX, 'runner imports SuperflexEnv; superflexpy not importable here')
class TestRunnerProtocolDispatch(unittest.TestCase):
    """Runner protocol dispatch — uses _load_period failure to short-circuit."""

    def test_unknown_protocol_raises_value_error(self):
        from src.xaj_global_pilot.runner import run_single_model_basin
        with self.assertRaises(ValueError):
            run_single_model_basin('00000000', 'xaj_pdd', protocol='nonexistent')

    def test_repro_v01_labels_period_as_evaluation(self):
        from src.xaj_global_pilot import runner as runner_mod
        with patch.object(runner_mod, '_load_period', side_effect=RuntimeError('forced fail')):
            row = runner_mod.run_single_model_basin(
                '00000000', 'xaj_pdd', protocol='repro_v01',
            )
        self.assertEqual(row['period'], 'evaluation')
        self.assertEqual(row['run_status'], 'failed')

    def test_v02_labels_period_as_test(self):
        from src.xaj_global_pilot import runner as runner_mod
        with patch.object(runner_mod, '_load_period', side_effect=RuntimeError('forced fail')):
            row = runner_mod.run_single_model_basin(
                '00000000', 'xaj_pdd', protocol='v02',
            )
        self.assertEqual(row['period'], 'test')


@unittest.skipUnless(_HAS_SUPERFLEX, 'superflexpy not importable in this environment')
class TestSuperflexEnvNRestarts(unittest.TestCase):
    """SuperflexEnv._calibrate_sfpy must run N independent CMA-ES restarts."""

    @staticmethod
    def _build_trivial_env():
        from hydroagent.environment import SuperflexEnv
        env = SuperflexEnv()
        env.parse_structure({
            'layers': [{'id': 'soil', 'type': 'PowerReservoir', 'inputs': ['prcp']}],
            'system_output': ['soil'],
            'lag_functions': [],
        })
        return env

    @staticmethod
    def _make_dummy_data(n=20):
        idx = pd.date_range('2000-01-01', periods=n)
        forcing = pd.DataFrame({'prcp': np.zeros(n)}, index=idx)
        obs = pd.Series(np.ones(n) * 0.1, index=idx, name='qobs')
        return forcing, obs

    def test_n_restarts_drives_cmaes_call_count_and_seeds(self):
        env = self._build_trivial_env()
        forcing, obs = self._make_dummy_data()

        with patch('hydroagent.environment.cma.CMAEvolutionStrategy') as mock_cma_cls:
            mock_es = MagicMock()
            mock_es.result.xbest = np.array([0.5, 0.5])
            mock_cma_cls.return_value = mock_es

            env._calibrate_sfpy(forcing, obs, n_trials=10, n_restarts=4)

        self.assertEqual(mock_cma_cls.call_count, 4)
        seeds = [call.args[2]['seed'] for call in mock_cma_cls.call_args_list]
        self.assertEqual(seeds, [42, 1042, 2042, 3042])

    def test_n_restarts_default_is_one(self):
        env = self._build_trivial_env()
        forcing, obs = self._make_dummy_data()

        with patch('hydroagent.environment.cma.CMAEvolutionStrategy') as mock_cma_cls:
            mock_es = MagicMock()
            mock_es.result.xbest = np.array([0.5, 0.5])
            mock_cma_cls.return_value = mock_es

            env._calibrate_sfpy(forcing, obs, n_trials=10)

        self.assertEqual(mock_cma_cls.call_count, 1)

    def test_n_restarts_zero_raises(self):
        env = self._build_trivial_env()
        forcing, obs = self._make_dummy_data()
        with self.assertRaises(ValueError):
            env._calibrate_sfpy(forcing, obs, n_trials=10, n_restarts=0)


if __name__ == '__main__':
    unittest.main()
