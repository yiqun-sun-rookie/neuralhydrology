"""Offline verification of the v12 crash-bug fixes (no LLM/API calls).

Re-calibrates the exact structures that produced NSE = -999 in the v12 run for
the two crash basins, using the patched SuperflexEnv. If the penalty/ValueError
fixes work, these should now return finite (and hopefully good) NSE instead of
-999.

Run:
    PYTHONPATH=src python src/hydroagent/scripts/_offline_bugfix_check.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'src'))

from hydroagent.data_loading import load_camels_basin
from hydroagent.environment import SuperflexEnv

V12_DIR = ROOT / 'results' / '07_hydroagent' / 'v12_explore_deepseek'
CRASH_BASINS = ['13313000', '10348850']


def load_iter1_structure(basin_id: str) -> dict:
    matches = sorted(V12_DIR.glob(f'{basin_id}_deepseek_*'))
    if not matches:
        raise FileNotFoundError(f'No v12 result dir for {basin_id}')
    sj = matches[-1] / 'structures.jsonl'
    with open(sj, 'r', encoding='utf-8') as f:
        first = json.loads(f.readline())
    return first['structure']


def main() -> int:
    print('=' * 70)
    print('Offline bug-fix verification (patched SuperflexEnv, no API)')
    print('=' * 70)
    all_ok = True
    for basin_id in CRASH_BASINS:
        structure = load_iter1_structure(basin_id)
        forcing, obs, area = load_camels_basin(basin_id)
        env = SuperflexEnv()
        env.parse_structure(structure)
        result = env.auto_calibrate(forcing, obs, n_trials=2000, n_restarts=1)
        nse = result['nse']
        status = 'OK (finite, escaped -999)' if nse > -900 else 'STILL CRASHED'
        if nse <= -900:
            all_ok = False
        print(f"\n{basin_id}  [{structure.get('model_name')}]  "
              f"{len(forcing)}d  area={area:.1f}km2")
        print(f"    calib NSE = {nse:.4f}   ->  {status}")
    print('\n' + '=' * 70)
    print('RESULT:', 'ALL RECOVERED' if all_ok else 'SOME STILL CRASHING')
    print('=' * 70)
    return 0 if all_ok else 1


if __name__ == '__main__':
    raise SystemExit(main())
