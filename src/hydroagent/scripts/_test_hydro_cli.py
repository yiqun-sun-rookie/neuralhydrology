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


TESTS = {
    'components': test_components,
}


def main():
    names = sys.argv[1:] or list(TESTS)
    for n in names:
        TESTS[n]()
    print(f'ALL OK ({len(names)} test(s))')


if __name__ == '__main__':
    main()
