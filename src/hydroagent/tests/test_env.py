import unittest
import numpy as np
import pandas as pd
import sys
import os

# Add project root
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../../..')))

try:
    from hydroagent.environment import SuperflexEnv
except ImportError:
    # Fallback for direct execution
    sys.path.append(os.getcwd())
    from hydroagent.environment import SuperflexEnv

class TestSuperflexEnv(unittest.TestCase):
    def setUp(self):
        dates = pd.date_range(start='2000-01-01', periods=100, freq='h')
        self.forcing = pd.DataFrame({
            'prcp': np.random.uniform(0, 10, size=100),
            'ep': np.random.uniform(0, 5, size=100)
        }, index=dates)
        
        self.obs = pd.Series(
            self.forcing['prcp'] * 0.5 + np.random.normal(0, 0.1, size=100),
            index=dates
        )
        self.obs[self.obs < 0] = 0

        # Note: GammaLag currently not fully implemented, using simpler structure
        self.structure_json = {
            'model_name': 'test_v1',
            'layers': [
                {
                    'id': 'soil',
                    'type': 'UnsaturatedReservoir',
                    'parameters': ['Smax', 'beta'],
                    'inputs': ['prcp', 'ep'],
                    'outputs': ['out_flux']
                },
                {
                    'id': 'fast',
                    'type': 'PowerReservoir',
                    'parameters': ['k', 'alpha'],
                    'inputs': ['soil.out_flux'],
                    'outputs': ['q_fast']
                }
            ],
            'lag_functions': [],
            'system_output': ['fast']
        }
        
    def test_parse_and_run(self):
        env = SuperflexEnv()
        env.parse_structure(self.structure_json)
        self.assertIn('soil', env.elements)
        q_sim = env.run_simulation(self.forcing)
        self.assertEqual(len(q_sim), 100)
        print(f'\n[Test] Mean Qsim: {q_sim.mean():.4f}')

    def test_auto_calibrate(self):
        env = SuperflexEnv()
        env.parse_structure(self.structure_json)
        result = env.auto_calibrate(self.forcing, self.obs)
        print(f"\n[Test] Calibrated NSE: {result['nse']:.4f}")
        self.assertTrue(result['nse'] > -999.0)

if __name__ == '__main__':
    unittest.main()

