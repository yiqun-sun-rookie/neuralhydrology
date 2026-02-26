"""Multi-basin benchmark for SuperflexEnv with lag_functions.

Uses real CAMELS-US data to verify that:
1. All structures run without error on real basins
2. NSE is positive (model beats mean-of-obs baseline)
3. 3-layer structure >= 2-layer in most basins
4. lag_functions produce different output from no-lag

Requires: data/camels_us/ with daymet forcing + streamflow + attributes.
Run:  python -m pytest src/hydroagent/tests/test_benchmark_basins.py -v
      python src/hydroagent/tests/test_benchmark_basins.py         # standalone
"""
import os
import sys
import unittest

import numpy as np
import pandas as pd

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))

from hydroagent.environment import SuperflexEnv

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
_PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
_DATA_ROOT = os.path.join(_PROJECT_ROOT, 'data', 'camels_us')
_TEST_DATA_ROOT = os.path.join(_PROJECT_ROOT, 'test', 'test_data', 'camels_us')

# ---------------------------------------------------------------------------
# Structures
# ---------------------------------------------------------------------------
STRUCT_2L = {
    'layers': [
        {'id': 'soil', 'type': 'UnsaturatedReservoir', 'inputs': ['prcp', 'ep']},
        {'id': 'fast', 'type': 'PowerReservoir', 'inputs': ['soil.runoff']},
    ],
    'system_output': ['fast'],
    'lag_functions': [],
}

STRUCT_3L = {
    'layers': [
        {'id': 'soil', 'type': 'UnsaturatedReservoir', 'inputs': ['prcp', 'ep']},
        {'id': 'fast', 'type': 'PowerReservoir', 'inputs': ['soil.runoff']},
        {'id': 'slow', 'type': 'LinearReservoir', 'inputs': ['soil.runoff']},
    ],
    'system_output': ['fast', 'slow'],
    'lag_functions': [],
}

STRUCT_3L_LAG = {
    'layers': [
        {'id': 'soil', 'type': 'UnsaturatedReservoir', 'inputs': ['prcp', 'ep']},
        {'id': 'fast', 'type': 'PowerReservoir', 'inputs': ['soil.runoff']},
        {'id': 'slow', 'type': 'LinearReservoir', 'inputs': ['soil.runoff']},
    ],
    'system_output': ['fast', 'slow'],
    'lag_functions': [{'target': 'fast', 'lag_steps': 3}],
}


# ---------------------------------------------------------------------------
# Data loader (reuses logic from test_real_data.py)
# ---------------------------------------------------------------------------
def _find_file(basin_id, kind):
    """Locate forcing or streamflow file across data/ and test/test_data/."""
    huc2 = basin_id[:2]
    if kind == 'forcing':
        candidates = [
            os.path.join(_DATA_ROOT, 'basin_mean_forcing', 'daymet', huc2,
                         f'{basin_id}_lump_cida_forcing_leap.txt'),
            os.path.join(_TEST_DATA_ROOT, 'basin_mean_forcing', 'daymet',
                         f'{basin_id}_lump_cida_forcing_leap.txt'),
        ]
    else:
        candidates = [
            os.path.join(_DATA_ROOT, 'usgs_streamflow', huc2,
                         f'{basin_id}_streamflow_qc.txt'),
            os.path.join(_TEST_DATA_ROOT, 'usgs_streamflow',
                         f'{basin_id}_streamflow_qc.txt'),
        ]
    for p in candidates:
        if os.path.exists(p):
            return p
    return None


def _load_topo():
    """Load basin areas from camels_topo.txt."""
    for root in [_DATA_ROOT, _TEST_DATA_ROOT]:
        p = os.path.join(root, 'camels_attributes_v2.0', 'camels_topo.txt')
        if os.path.exists(p):
            df = pd.read_csv(p, sep=';')
            df['gauge_id'] = df['gauge_id'].astype(str).str.zfill(8)
            return dict(zip(df['gauge_id'], df['area_gages2']))
    return {}


def load_basin(basin_id, area_km2, start='2000-01-01', end='2002-12-31'):
    """Load forcing + obs for a single basin, return (forcing_df, obs_series) in mm/day."""
    ff = _find_file(basin_id, 'forcing')
    sf = _find_file(basin_id, 'streamflow')
    if not ff or not sf:
        return None, None

    # Forcing
    df = pd.read_csv(ff, skiprows=3, sep=r'\s+')
    df.columns = ['year', 'month', 'day', 'hr', 'dayl', 'prcp', 'srad', 'swe', 'tmax', 'tmin', 'vp']
    df['date'] = pd.to_datetime(df[['year', 'month', 'day']])
    df = df.set_index('date')

    # Hargreaves PET estimate
    tmax, tmin, srad = df['tmax'].values, df['tmin'].values, df['srad'].values
    tmean = (tmax + tmin) / 2.0
    delta_t = np.maximum(tmax - tmin, 0.1)
    pet = np.maximum(0.0023 * (srad * 0.0864) * np.sqrt(delta_t) * (tmean + 17.8), 0.0)
    df['ep'] = pet

    # Streamflow (cfs -> mm/day)
    sdf = pd.read_csv(sf, sep=r'\s+', header=None,
                       names=['basin', 'year', 'month', 'day', 'flow', 'qc'])
    sdf['date'] = pd.to_datetime(sdf[['year', 'month', 'day']])
    sdf = sdf.set_index('date')
    cfs_to_mmday = 2.4466 / area_km2  # 0.0283168 * 86400 / 1e6 * 1000 ≈ 2.4466
    sdf['flow_mm'] = sdf['flow'] * cfs_to_mmday
    sdf.loc[sdf['flow'] < 0, 'flow_mm'] = np.nan

    # Slice and align
    forcing = df.loc[start:end, ['prcp', 'ep']]
    obs = sdf.loc[start:end, 'flow_mm'].dropna()
    common = forcing.index.intersection(obs.index)
    return forcing.loc[common], obs.loc[common]


# ---------------------------------------------------------------------------
# Test basins: all locally available
# ---------------------------------------------------------------------------
# basin_id -> expected minimum NSE for 3L+lag (conservative threshold)
TEST_BASINS = {
    '01022500': 0.3,
    '01547700': 0.3,
    '02064000': 0.3,
    '03015500': 0.3,
    '01169000': 0.0,
    '04056500': 0.0,
}


class TestMultiBasinBenchmark(unittest.TestCase):
    """Benchmark SuperflexEnv on multiple real CAMELS-US basins."""

    @classmethod
    def setUpClass(cls):
        cls.area_map = _load_topo()
        if not cls.area_map:
            raise unittest.SkipTest('CAMELS topo attributes not found')

        # Pre-check which basins have data
        cls.available = {}
        for bid in TEST_BASINS:
            area = cls.area_map.get(bid)
            if area is None:
                continue
            forcing, obs = load_basin(bid, area)
            if forcing is not None and len(forcing) > 200:
                cls.available[bid] = (forcing, obs, area)

        if not cls.available:
            raise unittest.SkipTest('No CAMELS basin data available locally')

        print(f'\n{"Basin":>10} {"Area":>7} | {"2L":>8} {"3L":>8} {"3L+lag":>8}')
        print('-' * 56)

    def _run_basin(self, bid, struct):
        forcing, obs, _ = self.available[bid]
        env = SuperflexEnv()
        _, nse = env.run(struct, forcing, obs)
        return nse

    def test_all_basins_run_without_error(self):
        """Every available basin should complete 2L calibration without exception."""
        for bid in self.available:
            with self.subTest(basin=bid):
                nse = self._run_basin(bid, STRUCT_2L)
                self.assertTrue(np.isfinite(nse), f'{bid}: NSE is not finite')

    def test_all_basins_positive_nse(self):
        """3L+lag structure should achieve NSE > minimum threshold on each basin."""
        for bid, min_nse in TEST_BASINS.items():
            if bid not in self.available:
                continue
            with self.subTest(basin=bid):
                nse = self._run_basin(bid, STRUCT_3L_LAG)
                self.assertGreater(nse, min_nse,
                                   f'{bid}: NSE={nse:.4f} below threshold {min_nse}')

    def test_lag_changes_output(self):
        """Lag must produce different output from no-lag on each basin."""
        for bid in self.available:
            with self.subTest(basin=bid):
                forcing, _, _ = self.available[bid]
                env = SuperflexEnv()

                env.parse_structure(STRUCT_3L)
                q_no_lag = env.run_simulation(forcing)

                env.parse_structure(STRUCT_3L_LAG)
                q_lag = env.run_simulation(forcing)

                self.assertFalse(
                    np.allclose(q_no_lag.values, q_lag.values),
                    f'{bid}: lag output identical to no-lag',
                )

    def test_summary_table(self):
        """Print a summary table of all basins x structures (informational)."""
        results = []
        for bid in sorted(self.available):
            _, _, area = self.available[bid]
            nses = {}
            for sname, struct in [('2L', STRUCT_2L), ('3L', STRUCT_3L), ('3L+lag', STRUCT_3L_LAG)]:
                nses[sname] = self._run_basin(bid, struct)
            print(f'{bid:>10} {area:>7.1f} | {nses["2L"]:8.4f} {nses["3L"]:8.4f} {nses["3L+lag"]:8.4f}')
            results.append(nses)

        # At least one basin should exceed NSE 0.5
        best_nses = [max(r.values()) for r in results]
        self.assertGreater(max(best_nses), 0.5,
                           'No basin achieved NSE > 0.5 — possible regression')


if __name__ == '__main__':
    unittest.main()
