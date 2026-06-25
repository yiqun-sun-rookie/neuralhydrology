"""Runnable smoke tests for hydro_cli.py (run with the forecast_system_lite python).

Usage:
    python src/hydroagent/scripts/_test_hydro_cli.py            # run all
    python src/hydroagent/scripts/_test_hydro_cli.py components # run one
"""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

PY = sys.executable
CLI = 'src/hydroagent/scripts/hydro_cli.py'
BASIN = '01022500'  # Maine benchmark basin with clean data

GOOD_STRUCTURE = {
    'model_name': 'HBV_light_parallel',
    'layers': [
        {'id': 'snow', 'type': 'SnowReservoir', 'parameters': {}, 'inputs': ['prcp', 'temperature']},
        {'id': 'soil', 'type': 'UnsaturatedReservoir', 'parameters': {}, 'inputs': ['prcp', 'ep']},
        {'id': 'fast', 'type': 'PowerReservoir', 'parameters': {}, 'inputs': ['soil.runoff']},
        {'id': 'slow', 'type': 'LinearReservoir', 'parameters': {}, 'inputs': ['soil.runoff']},
    ],
    'lag_functions': [],
    'system_output': ['fast', 'slow'],
}


def _run(*args):
    return subprocess.run([PY, CLI, *args], capture_output=True, text=True)


def test_components():
    r = _run('components')
    assert r.returncode == 0, f'exit={r.returncode} stderr_tail={r.stderr[-500:]}'
    data = json.loads(r.stdout)  # parses => stdout is clean JSON (no solver spam)
    types = {c['type'] for c in data['components']}
    assert 'UnsaturatedReservoir' in types, types
    assert 'SnowReservoir' in types, types
    assert data['components'], 'no components'
    assert any(c['bounds'] for c in data['components']), 'no bounds present'
    assert 'schema' in data and 'example' in data
    assert {l['type'] for l in data['lag_functions']} >= {'HalfTriangularLag'}
    print('test_components OK')


def test_basin_info():
    r = _run('basin-info', BASIN, '--protocol', 'fast')
    assert r.returncode == 0, f'exit={r.returncode} stderr_tail={r.stderr[-500:]}'
    data = json.loads(r.stdout)
    assert data['basin_id'] == BASIN
    assert data['area_km2'] > 0, data
    assert data['n_days'] > 300, data
    assert data['protocol'] == 'fast'
    assert data['calib_window'][0] == '1990-10-01'
    print('test_basin_info OK')


def test_evaluate_invalid():
    bad = {'model_name': 'bad', 'layers': [
        {'id': 'x', 'type': 'NotAComponent', 'parameters': {}, 'inputs': ['prcp']}]}
    with tempfile.NamedTemporaryFile('w', suffix='.json', delete=False) as fh:
        json.dump(bad, fh)
        path = fh.name
    r = _run('evaluate', BASIN, '--structure', path, '--protocol', 'fast')
    assert r.returncode == 2, f'exit={r.returncode} stdout={r.stdout[:300]}'
    data = json.loads(r.stdout)
    assert data['valid'] is False
    assert any('NotAComponent' in e for e in data['errors']), data['errors']
    print('test_evaluate_invalid OK')


def test_evaluate_fast():
    out = tempfile.mkdtemp(prefix='hydrocli_')
    with tempfile.NamedTemporaryFile('w', suffix='.json', delete=False) as fh:
        json.dump(GOOD_STRUCTURE, fh)
        path = fh.name
    r = _run('evaluate', BASIN, '--structure', path, '--protocol', 'fast',
             '--trials', '300', '--out', out)
    assert r.returncode == 0, f'exit={r.returncode} stderr_tail={r.stderr[-800:]}'
    data = json.loads(r.stdout)  # clean stdout despite solver noise on stderr
    assert data['valid'] is True, data
    assert isinstance(data['nse'], float) and data['nse'] > -900, data['nse']
    assert data['eval_nse'] is None
    assert 'metrics' in data['diagnosis'] and 'semantic_feedback' in data['diagnosis']
    assert Path(data['history_path']).exists()
    hist_lines = Path(data['history_path']).read_text().strip().splitlines()
    assert len(hist_lines) == 1, 'history should have one record'
    print(f'test_evaluate_fast OK (nse={data["nse"]:.3f})')


def test_evaluate_repro():
    out = tempfile.mkdtemp(prefix='hydrocli_repro_')
    with tempfile.NamedTemporaryFile('w', suffix='.json', delete=False) as fh:
        json.dump(GOOD_STRUCTURE, fh)
        path = fh.name
    r = _run('evaluate', BASIN, '--structure', path, '--protocol', 'repro_v01',
             '--trials', '300', '--out', out)
    assert r.returncode == 0, f'exit={r.returncode} stderr_tail={r.stderr[-800:]}'
    data = json.loads(r.stdout)
    assert data['valid'] is True, data
    assert isinstance(data['eval_nse'], float), data['eval_nse']
    assert data['eval_nse'] > -900, data['eval_nse']
    print(f'test_evaluate_repro OK (eval_nse={data["eval_nse"]:.3f})')


TESTS = {
    'components': test_components,
    'basin_info': test_basin_info,
    'evaluate_invalid': test_evaluate_invalid,
    'evaluate_fast': test_evaluate_fast,
    'evaluate_repro': test_evaluate_repro,
}


def main():
    names = sys.argv[1:] or list(TESTS)
    for n in names:
        TESTS[n]()
    print(f'ALL OK ({len(names)} test(s))')


if __name__ == '__main__':
    main()
