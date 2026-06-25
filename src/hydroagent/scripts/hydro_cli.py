"""hydro_cli.py — thin CLI exposing SuperflexEnv + HydroDiagnostician.

Lets Claude Code's Claude drive conceptual rainfall-runoff structure discovery:
  components            -> component vocabulary + JSON schema + example
  basin-info <id>       -> basin attributes + resolved protocol windows
  evaluate <id> ...     -> validate -> calibrate -> diagnose -> JSON result

stdout carries ONLY the JSON result; all SuperflexPy numerical noise goes to stderr.
"""
from __future__ import annotations

import argparse
import contextlib
import json
import os
import sys
import warnings
from datetime import datetime
from pathlib import Path

# Same idiom as run_batch.py: '../..' from scripts/ lands on src/, making
# `hydroagent` importable regardless of cwd.
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))

from hydroagent.environment import (  # noqa: E402
    SuperflexEnv, _REGISTRY, _BASEELEM_REGISTRY, _LAG_REGISTRY,
)

# Protocol -> data-loading config. 'fast' mirrors the v12 in-sample default;
# 'repro_v01' aligns with the 531 benchmark (Maurer + Priestley-Taylor + split).
PROTOCOLS = {
    'fast': {
        'forcing': 'daymet', 'pet_method': 'oudin',
        'calib': ('1990-10-01', '1993-09-30'), 'eval': None,
    },
    'repro_v01': {
        'forcing': 'maurer_extended', 'pet_method': 'priestley_taylor',
        'calib': ('1999-10-01', '2008-09-30'), 'eval': ('1989-10-01', '1999-09-30'),
    },
}

_EXAMPLE_STRUCTURE = {
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


def _emit(obj, code=0):
    """Write the JSON result to the REAL stdout and exit. Call OUTSIDE _quiet()."""
    json.dump(obj, sys.stdout, indent=2, default=str)
    sys.stdout.write('\n')
    sys.stdout.flush()
    sys.exit(code)


@contextlib.contextmanager
def _quiet():
    """Redirect stdout->stderr and silence warnings while calling noisy libs."""
    old = sys.stdout
    sys.stdout = sys.stderr
    with warnings.catch_warnings():
        warnings.simplefilter('ignore')
        try:
            yield
        finally:
            sys.stdout = old


def cmd_components(args):
    comps = []
    for name, reg in {**_REGISTRY, **_BASEELEM_REGISTRY}.items():
        comps.append({
            'type': name,
            'input_map': reg.get('input_map'),
            'params': reg.get('params', {}),
            'bounds': reg.get('bounds', {}),
            'output_index': reg.get('output_index', 0),
        })
    lags = [{'type': n, 'default': r['default'], 'bounds': list(r['bounds'])}
            for n, r in _LAG_REGISTRY.items()]
    schema = {
        'model_name': 'str — descriptive name',
        'layers': [{
            'id': 'str — unique layer id',
            'type': 'one of the component types above',
            'parameters': '{} to use defaults, or {param: value} overrides',
            'inputs': ["forcing name ('prcp'|'ep'|'temperature') or '<layer_id>.<anything>'"],
        }],
        'lag_functions': [{'target': '<layer id>', 'type': '<lag type>', 'lag_steps': 'optional float'}],
        'system_output': ['<layer id>', '... summed to form total streamflow'],
    }
    _emit({'components': comps, 'lag_functions': lags, 'schema': schema,
           'example': _EXAMPLE_STRUCTURE})


def build_parser():
    p = argparse.ArgumentParser(prog='hydro_cli', description='HydroAgent discovery CLI')
    sub = p.add_subparsers(dest='cmd', required=True)
    sub.add_parser('components', help='Print component library + schema + example')
    return p


def main():
    parser = build_parser()
    args = parser.parse_args()
    if args.cmd == 'components':
        cmd_components(args)


if __name__ == '__main__':
    main()
