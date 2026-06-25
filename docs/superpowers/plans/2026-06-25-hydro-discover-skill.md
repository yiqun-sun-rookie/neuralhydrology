# hydro-discover Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose the existing HydroAgent calibration + diagnosis environment as a thin CLI plus a Claude Code skill, so CC CLI's Claude becomes the structure-design brain (replacing weak DeepSeek) for interactive conceptual rainfall-runoff model discovery.

**Architecture:** A single CLI (`hydro_cli.py`) wraps the existing `SuperflexEnv` (CMA-ES calibration) and `HydroDiagnostician` (24-metric diagnosis) behind three subcommands — `components`, `basin-info`, `evaluate` — emitting clean JSON on stdout (all solver noise routed to stderr). A skill (`SKILL.md`) teaches Claude to drive the discovery loop: read vocabulary → read basin → propose/evaluate/refine structures → finalize under the `repro_v01` protocol. The existing `ClaudeClient` backend is the later reproducible automated path.

**Tech Stack:** Python 3 (run with the `forecast_system_lite` conda env: superflexpy, cma, numba, pandas), argparse, Claude Code skills (markdown).

**Spec:** `docs/superpowers/specs/2026-06-25-hydroagent-cc-skill-design.md`

**Runtime note:** Every command below runs with the env python and project root as cwd:
`PYEXE="C:/Users/yiqun/anaconda3/envs/forecast_system_lite/python.exe"`
`hydro_cli.py` self-inserts `src/` on `sys.path` (same idiom as `run_batch.py`), so no `PYTHONPATH` is required, but setting `PYTHONPATH=src` is harmless.

---

## File Structure

- **Create** `src/hydroagent/scripts/hydro_cli.py` — the CLI (3 subcommands + shared helpers + protocol config). One focused file (~280 lines).
- **Create** `src/hydroagent/scripts/_test_hydro_cli.py` — runnable smoke tests (NOT pytest; pytest collects only `test/` and lacks the superflexpy env). Dispatches by test name.
- **Create** `.claude/skills/hydro-discover/SKILL.md` — the skill instructions.
- **Modify** `src/hydroagent/agent.py` — update the stale `ClaudeClient` default model id (§9 of spec).
- **Modify** `src/hydroagent/scripts/run_batch.py` — update the `claude` backend default model id.

---

## Task 0: Commit the pending v12 bug fixes (clean the working tree)

The 2026-06-24 crash fixes (environment.py), the floor-default fix (agent.py), and the offline verification script are uncommitted. Commit them first so later skill commits don't entangle them. `agent.py` also carries the prior session's exploration-prompt edits — the message notes this transparently.

**Files:**
- Modify: `src/hydroagent/environment.py` (already edited — ValueError catch, crash penalty 1e6, finite guard)
- Modify: `src/hydroagent/agent.py` (already edited — floor_nse default -900; plus prior-session prompt edits)
- Create: `src/hydroagent/scripts/_offline_bugfix_check.py` (already created)

- [ ] **Step 1: Confirm the diff is what we expect**

Run: `git diff --stat src/hydroagent/environment.py src/hydroagent/agent.py`
Expected: both files listed with small insertion counts.

- [ ] **Step 2: Commit (scoped to these three paths)**

```bash
git add src/hydroagent/environment.py src/hydroagent/agent.py src/hydroagent/scripts/_offline_bugfix_check.py
git commit -m "fix(idea07): contain v12 calibration crashes + floor mis-kill

- environment.py: catch ValueError (Pegasus 'fa and fb same sign') at element
  solve; crash penalty 2.0 -> 1e6 (CMA no longer attracted to crash region);
  finite-guard the re-sim NSE.
- agent.py: floor_nse default 0.0 -> -900 (only kill genuine -999 crashes, not
  valid-but-poor structures). NOTE: agent.py also carries prior-session
  exploration-nudge prompt edits used by the v12 run.
- _offline_bugfix_check.py: offline recalibration of the two crash basins.

Rerun result: 13313000 -999->0.9618, 10348850 -999->0.5763,
08271000 floor-killed->ran full 12 iters (0.0131); 18/18 no crashes.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
git log --oneline -1
```
Expected: one new commit; `git status` shows environment.py/agent.py no longer modified.

---

## Task 1: `components` subcommand + CLI skeleton + clean-output helpers

**Files:**
- Create: `src/hydroagent/scripts/hydro_cli.py`
- Create: `src/hydroagent/scripts/_test_hydro_cli.py`

- [ ] **Step 1: Write the failing test**

Create `src/hydroagent/scripts/_test_hydro_cli.py`:

```python
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"$PYEXE" src/hydroagent/scripts/_test_hydro_cli.py components`
Expected: FAIL — `hydro_cli.py` does not exist yet (FileNotFoundError / non-zero exit / JSONDecodeError).

- [ ] **Step 3: Write minimal implementation**

Create `src/hydroagent/scripts/hydro_cli.py`:

```python
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"$PYEXE" src/hydroagent/scripts/_test_hydro_cli.py components`
Expected: PASS — prints `test_components OK` then `ALL OK (1 test(s))`.

- [ ] **Step 5: Commit**

```bash
git add src/hydroagent/scripts/hydro_cli.py src/hydroagent/scripts/_test_hydro_cli.py
git commit -m "feat(idea07): hydro_cli components subcommand + clean-output helpers

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `basin-info` subcommand + protocol resolution

**Files:**
- Modify: `src/hydroagent/scripts/hydro_cli.py` (add `cmd_basin_info`, register subparser)
- Modify: `src/hydroagent/scripts/_test_hydro_cli.py` (add `test_basin_info`)

- [ ] **Step 1: Write the failing test**

Add to `_test_hydro_cli.py` (and register in `TESTS`):

```python
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
```

Update `TESTS`:
```python
TESTS = {
    'components': test_components,
    'basin_info': test_basin_info,
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"$PYEXE" src/hydroagent/scripts/_test_hydro_cli.py basin_info`
Expected: FAIL — `invalid choice: 'basin-info'` (subcommand not registered).

- [ ] **Step 3: Write minimal implementation**

In `hydro_cli.py`, add the import near the top imports:

```python
from hydroagent.data_loading import load_camels_basin, load_basin_metadata  # noqa: E402
```

Add the function (after `cmd_components`):

```python
def cmd_basin_info(args):
    proto = PROTOCOLS[args.protocol]
    cs, ce = proto['calib']
    with _quiet():
        try:
            meta = load_basin_metadata(args.basin_id)
        except Exception:
            meta = None
        forcing, obs, area = load_camels_basin(
            args.basin_id, start_date=cs, end_date=ce,
            forcing=proto['forcing'], pet_method=proto['pet_method'])
    _emit({
        'basin_id': args.basin_id,
        'protocol': args.protocol,
        'area_km2': float(area),
        'n_days': int(len(forcing)),
        'calib_window': list(proto['calib']),
        'eval_window': list(proto['eval']) if proto['eval'] else None,
        'attributes': meta,
    })
```

In `build_parser`, replace the body with:

```python
    p = argparse.ArgumentParser(prog='hydro_cli', description='HydroAgent discovery CLI')
    sub = p.add_subparsers(dest='cmd', required=True)
    sub.add_parser('components', help='Print component library + schema + example')

    bi = sub.add_parser('basin-info', help='Print basin attributes + protocol windows')
    bi.add_argument('basin_id')
    bi.add_argument('--protocol', choices=list(PROTOCOLS), default='fast')
    return p
```

In `main`, add the dispatch branch:

```python
    elif args.cmd == 'basin-info':
        cmd_basin_info(args)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"$PYEXE" src/hydroagent/scripts/_test_hydro_cli.py basin_info`
Expected: PASS — `test_basin_info OK`.

- [ ] **Step 5: Commit**

```bash
git add src/hydroagent/scripts/hydro_cli.py src/hydroagent/scripts/_test_hydro_cli.py
git commit -m "feat(idea07): hydro_cli basin-info subcommand + protocol config

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: structure validator + `evaluate` invalid path (exit 2)

**Files:**
- Modify: `src/hydroagent/scripts/hydro_cli.py` (add `_validate_structure`, `cmd_evaluate` skeleton with invalid path, subparser)
- Modify: `src/hydroagent/scripts/_test_hydro_cli.py` (add `test_evaluate_invalid`)

- [ ] **Step 1: Write the failing test**

Add to `_test_hydro_cli.py` (and register):

```python
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
```

Register:
```python
    'evaluate_invalid': test_evaluate_invalid,
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"$PYEXE" src/hydroagent/scripts/_test_hydro_cli.py evaluate_invalid`
Expected: FAIL — `invalid choice: 'evaluate'`.

- [ ] **Step 3: Write minimal implementation**

In `hydro_cli.py`, add the validator (after `_EXAMPLE_STRUCTURE`):

```python
def _validate_structure(structure):
    """Lightweight pre-calibration validation. Returns a list of error strings."""
    errors = []
    if not isinstance(structure, dict):
        return ['structure must be a JSON object']
    layers = structure.get('layers')
    if not isinstance(layers, list) or not layers:
        return ["'layers' must be a non-empty list"]
    known = set(_REGISTRY) | set(_BASEELEM_REGISTRY)
    ids = set()
    for i, lyr in enumerate(layers):
        if not isinstance(lyr, dict):
            errors.append(f'layer[{i}] is not an object')
            continue
        lid, ltype = lyr.get('id'), lyr.get('type')
        if not lid:
            errors.append(f'layer[{i}] missing "id"')
        else:
            ids.add(lid)
        if ltype not in known:
            errors.append(f"layer '{lid}' has unknown component type {ltype!r}")
    for lyr in layers if isinstance(layers, list) else []:
        if not isinstance(lyr, dict):
            continue
        for inp in lyr.get('inputs', []) or []:
            if isinstance(inp, str) and '.' in inp:
                src = inp.split('.')[0]
                if src not in ids:
                    errors.append(
                        f"layer '{lyr.get('id')}' input {inp!r} references undefined id {src!r}")
    for lc in structure.get('lag_functions', []) or []:
        lt = lc.get('type', 'HalfTriangularLag')
        if lt not in _LAG_REGISTRY:
            errors.append(f"unknown lag type {lt!r}")
    return errors
```

Add the (initial) `cmd_evaluate` handling only the invalid path:

```python
def cmd_evaluate(args):
    structure = json.loads(Path(args.structure).read_text(encoding='utf-8'))
    errors = _validate_structure(structure)
    if errors:
        _emit({'valid': False, 'basin_id': args.basin_id, 'protocol': args.protocol,
               'errors': errors, 'nse': None, 'eval_nse': None}, code=2)
    # (valid path implemented in Task 4)
    _emit({'valid': True, 'basin_id': args.basin_id, 'note': 'calibration not yet implemented'})
```

In `build_parser`, before `return p` add:

```python
    ev = sub.add_parser('evaluate', help='Validate, calibrate, diagnose a structure')
    ev.add_argument('basin_id')
    ev.add_argument('--structure', required=True, help='Path to structure JSON')
    ev.add_argument('--protocol', choices=list(PROTOCOLS), default='fast')
    ev.add_argument('--trials', type=int, default=2000, help='CMA-ES n_trials')
    ev.add_argument('--out', default=None, help='Session output dir')
```

In `main`, add:

```python
    elif args.cmd == 'evaluate':
        cmd_evaluate(args)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"$PYEXE" src/hydroagent/scripts/_test_hydro_cli.py evaluate_invalid`
Expected: PASS — `test_evaluate_invalid OK`.

- [ ] **Step 5: Commit**

```bash
git add src/hydroagent/scripts/hydro_cli.py src/hydroagent/scripts/_test_hydro_cli.py
git commit -m "feat(idea07): hydro_cli structure validator + evaluate invalid path

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: `evaluate` fast protocol — calibrate + diagnose + history (the core)

**Files:**
- Modify: `src/hydroagent/scripts/hydro_cli.py` (complete `cmd_evaluate` valid path; add diagnosis import)
- Modify: `src/hydroagent/scripts/_test_hydro_cli.py` (add `test_evaluate_fast`)

- [ ] **Step 1: Write the failing test**

Add to `_test_hydro_cli.py` (and register). Uses the known-good HBV-light parallel structure, low `--trials` for speed:

```python
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
```

Register:
```python
    'evaluate_fast': test_evaluate_fast,
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"$PYEXE" src/hydroagent/scripts/_test_hydro_cli.py evaluate_fast`
Expected: FAIL — current `cmd_evaluate` returns `{'valid': True, 'note': ...}` with no `nse`/`diagnosis` (KeyError / assertion).

- [ ] **Step 3: Write minimal implementation**

In `hydro_cli.py`, add the diagnosis import:

```python
from hydroagent.diagnosis import HydroDiagnostician  # noqa: E402
```

Replace the placeholder valid path in `cmd_evaluate` (everything after the `if errors:` block) with:

```python
    proto = PROTOCOLS[args.protocol]
    cs, ce = proto['calib']
    out_dir = Path(args.out) if args.out else (
        Path('results/07_hydroagent/cc_discover')
        / f"{args.basin_id}_{datetime.now():%Y%m%d_%H%M%S}")
    out_dir.mkdir(parents=True, exist_ok=True)
    hist_path = out_dir / 'history.jsonl'

    payload, code = None, 0
    with _quiet():
        try:
            forcing, obs, area = load_camels_basin(
                args.basin_id, start_date=cs, end_date=ce,
                forcing=proto['forcing'], pet_method=proto['pet_method'])
            env = SuperflexEnv()
            try:
                env.parse_structure(structure)
            except Exception as e:
                payload, code = ({'valid': False, 'basin_id': args.basin_id,
                                  'protocol': args.protocol,
                                  'errors': [f'{type(e).__name__}: {e}'],
                                  'nse': None, 'eval_nse': None}, 2)
                raise _Done
            result = env.auto_calibrate(forcing, obs, n_trials=args.trials)
            nse = float(result['nse'])
            params = result['optimized_params']
            qsim = result['qsim']
            doctor = HydroDiagnostician()
            if nse > -900:
                diag = doctor.generate_report(obs, qsim)
            else:
                diag = {'metrics': doctor._empty_metrics(),
                        'semantic_feedback': ['Calibration failed (no valid fit).']}
            eval_nse = None
            if proto['eval']:
                es, ee = proto['eval']
                ef, eo, _ = load_camels_basin(
                    args.basin_id, start_date=es, end_date=ee,
                    forcing=proto['forcing'], pet_method=proto['pet_method'])
                eq = env.run_simulation(ef, params=params)
                eval_nse = float(SuperflexEnv._nse(eo, eq))

            n = sum(1 for _ in hist_path.open()) + 1 if hist_path.exists() else 1
            qpath = out_dir / f'qsim_{n:03d}.csv'
            qsim.to_csv(qpath, header=True)
            payload = {
                'valid': True,
                'basin_id': args.basin_id,
                'protocol': args.protocol,
                'model_name': structure.get('model_name', ''),
                'nse': nse,
                'eval_nse': eval_nse,
                'n_params': len(params),
                'params': params,
                'diagnosis': diag,
                'qsim_path': str(qpath),
                'history_path': str(hist_path),
                'warnings': [] if nse > -900 else ['calibration returned -999 sentinel'],
                'errors': [],
            }
            with hist_path.open('a', encoding='utf-8') as fh:
                rec = {k: payload[k] for k in
                       ('model_name', 'protocol', 'nse', 'eval_nse', 'params')}
                rec['metrics'] = diag['metrics']
                fh.write(json.dumps(rec, default=str) + '\n')
        except _Done:
            pass
        except Exception as e:  # unexpected internal error
            payload, code = ({'valid': False, 'basin_id': args.basin_id,
                              'protocol': args.protocol,
                              'errors': [f'internal: {type(e).__name__}: {e}'],
                              'nse': None, 'eval_nse': None}, 1)
    _emit(payload, code)
```

Add the sentinel exception near the top (after imports):

```python
class _Done(Exception):
    """Internal control-flow signal to break out of the _quiet() block early."""
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"$PYEXE" src/hydroagent/scripts/_test_hydro_cli.py evaluate_fast`
Expected: PASS — `test_evaluate_fast OK (nse=…)` (a finite NSE; ~15-30 s at 300 trials).

- [ ] **Step 5: Commit**

```bash
git add src/hydroagent/scripts/hydro_cli.py src/hydroagent/scripts/_test_hydro_cli.py
git commit -m "feat(idea07): hydro_cli evaluate fast protocol (calibrate+diagnose+history)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: `evaluate` repro_v01 protocol (out-of-sample `eval_nse`)

The `repro_v01` valid path is already coded in Task 4 (the `if proto['eval']:` branch). This task confirms the windows against the protocol doc and adds a test.

**Files:**
- Modify: `src/hydroagent/scripts/hydro_cli.py` (only if the verified windows differ from the Task-1 defaults)
- Modify: `src/hydroagent/scripts/_test_hydro_cli.py` (add `test_evaluate_repro`)

- [ ] **Step 1: Confirm the repro_v01 windows**

Run: `git grep -nE "1989|1999|2008|reverse|calib|maurer" -- docs/ src/lstm_fair_531 src/xaj_global_pilot | head -40`
Cross-check the 531 `repro_v01` protocol (reverse split: calibrate on the later decade, evaluate on 1989-10-01..1999-09-30; forcing `maurer_extended`; PET Priestley-Taylor). If the canonical calib window differs from `('1999-10-01','2008-09-30')`, update `PROTOCOLS['repro_v01']['calib']`/`['eval']` in `hydro_cli.py` accordingly. Record the source file in the commit message.

- [ ] **Step 2: Write the failing test**

Add to `_test_hydro_cli.py` (and register):

```python
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
```

Register:
```python
    'evaluate_repro': test_evaluate_repro,
```

- [ ] **Step 3: Run test to verify it fails (then passes)**

Run: `"$PYEXE" src/hydroagent/scripts/_test_hydro_cli.py evaluate_repro`
Expected: PASS if the windows are correct and basin `01022500` has Maurer forcing for both windows. If it FAILS with a data/load error, fix the windows/forcing in `PROTOCOLS['repro_v01']` (Step 1) and re-run until PASS.

- [ ] **Step 4: Run the full suite**

Run: `"$PYEXE" src/hydroagent/scripts/_test_hydro_cli.py`
Expected: `ALL OK (5 test(s))`.

- [ ] **Step 5: Commit**

```bash
git add src/hydroagent/scripts/hydro_cli.py src/hydroagent/scripts/_test_hydro_cli.py
git commit -m "feat(idea07): hydro_cli repro_v01 protocol verified + test

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: The `hydro-discover` skill

**Files:**
- Create: `.claude/skills/hydro-discover/SKILL.md`

- [ ] **Step 1: Confirm skill discovery location**

Run: `ls .claude/skills 2>/dev/null; echo '---'; git grep -n "skills" -- .claude 2>/dev/null | head`
If the repo has no `.claude/skills/` convention yet, create the directory (project skills live at `.claude/skills/<name>/SKILL.md`).

- [ ] **Step 2: Write the skill**

Create `.claude/skills/hydro-discover/SKILL.md`:

```markdown
---
name: hydro-discover
description: Use when discovering or improving a conceptual rainfall-runoff (hydrological) model STRUCTURE for a CAMELS-US basin — when the user wants Claude to act as the model-design brain (proposing/refining SuperflexPy component graphs) instead of the weak DeepSeek backend. Triggers: "discover a structure for basin X", "improve the HydroAgent model", "what conceptual model fits this basin".
---

# hydro-discover — Claude as the HydroAgent structure-design brain

You design conceptual rainfall-runoff model structures; a thin CLI calibrates and
diagnoses them. You own the loop. Run every command with the project's env python
from the project root:

    PYEXE="C:/Users/yiqun/anaconda3/envs/forecast_system_lite/python.exe"
    CLI="src/hydroagent/scripts/hydro_cli.py"

## Loop

1. **Load the vocabulary** — `"$PYEXE" "$CLI" components`. The JSON lists every
   component `type`, its parameter `bounds`, `input_map`, the structure `schema`,
   and a valid `example`. This is the source of truth — only use listed types.
2. **Read the basin** — `"$PYEXE" "$CLI" basin-info <basin_id> --protocol fast`.
   Note area, aridity, snow fraction; let climate guide the starting structure
   (e.g. snow component for snowy basins).
3. **Propose** — write `structure_001.json` (follow the schema; `parameters: {}`
   uses calibrated defaults). Evaluate:
   `"$PYEXE" "$CLI" evaluate <basin_id> --structure structure_001.json --protocol fast --trials 1000`
4. **Read the result JSON** — `nse` plus `diagnosis.semantic_feedback` and
   `diagnosis.metrics` (snow-season NSE, winter bias, recession, FDC slope, peak
   timing). Diagnose the SPECIFIC failure, don't guess.
5. **Refine** — write `structure_002.json` addressing the diagnosed failure, then
   evaluate. Repeat. Keep a running best; the CLI never discards your structures.
6. **Explore topology, not templates** — actively try series, cascade, and
   under-used components. The known failure mode (v12) is over-using the
   `soil → fast + slow` parallel template. Vary topology deliberately.
7. **Stop** when NSE plateaus (no improvement over ~3 refinements), a good target
   is reached, or returns diminish. YOU decide — there is no automatic stop.
8. **Finalize** — re-evaluate the best structure under `--protocol repro_v01`
   (out-of-sample). Report the best structure JSON, its `eval_nse`, and compare to
   baselines: LSTM 0.759, GR4J 0.653, XAJ 0.620, HBV 0.617.

## Rules

- Use `--protocol fast` while iterating (cheap); `--protocol repro_v01` only to
  finalize (out-of-sample, paper-comparable).
- A `valid:false` result (exit 2) means the structure is malformed — read
  `errors`, fix the JSON, re-evaluate. Do not proceed on an invalid structure.
- Keep one session dir (`--out results/07_hydroagent/cc_discover/<basin>_<run>`)
  so `history.jsonl` accumulates the full trace.
- Honesty: structures YOU find interactively are "Claude-assisted discovery", not
  automated reproducible discovery — never claim the latter in any write-up.
```

- [ ] **Step 3: Verify the skill is discoverable**

Restart/refresh the CC session if needed, then confirm `hydro-discover` appears in
the available skills list. (Manual check — no automated assertion.)

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/hydro-discover/SKILL.md
git commit -m "feat(idea07): hydro-discover skill (Claude as structure-design brain)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Claude API automated backend seam (update stale model id)

**Files:**
- Modify: `src/hydroagent/agent.py` (ClaudeClient default model id)
- Modify: `src/hydroagent/scripts/run_batch.py:119` (claude backend default model id)

- [ ] **Step 1: Update the model ids**

In `src/hydroagent/agent.py`, find `ClaudeClient.__init__` (around line 815):
change `model: str = 'claude-opus-4-6'` → `model: str = 'claude-opus-4-8'`.

In `src/hydroagent/scripts/run_batch.py` (around line 119):
change `ClaudeClient(api_key=api_key, model=model or 'claude-opus-4-6')`
→ `ClaudeClient(api_key=api_key, model=model or 'claude-opus-4-8')`.

- [ ] **Step 2: Connectivity check (skips gracefully without a key)**

Run:
```bash
"$PYEXE" -c "
import os, sys
sys.path.insert(0, 'src')
if not os.environ.get('ANTHROPIC_API_KEY'):
    print('SKIP: ANTHROPIC_API_KEY not set'); sys.exit(0)
from hydroagent.agent import ClaudeClient
print('PING:', repr(ClaudeClient().chat('You are terse.', 'Reply with the word PONG.')[:40]))
"
```
Expected: `SKIP: ANTHROPIC_API_KEY not set` (if no key) OR `PING: 'PONG'` (if a key is configured). Either is acceptable — this task only wires the seam; running an automated Claude batch is a separate, user-initiated action.

- [ ] **Step 3: Commit**

```bash
git add src/hydroagent/agent.py src/hydroagent/scripts/run_batch.py
git commit -m "chore(idea07): point ClaudeClient at claude-opus-4-8 (repro backend seam)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: End-to-end manual smoke (one real discovery turn)

**Files:** none (manual verification of the whole loop)

- [ ] **Step 1: Run the three commands a discovery turn uses**

```bash
PYEXE="C:/Users/yiqun/anaconda3/envs/forecast_system_lite/python.exe"
CLI="src/hydroagent/scripts/hydro_cli.py"
"$PYEXE" "$CLI" components | python -c "import sys,json; d=json.load(sys.stdin); print('components:', len(d['components']))"
"$PYEXE" "$CLI" basin-info 08271000 --protocol fast | python -c "import sys,json; d=json.load(sys.stdin); print('area', d['area_km2'])"
```
Expected: prints a component count (15) and a positive area — confirming clean JSON on stdout.

- [ ] **Step 2: Evaluate the example structure on the hard basin 08271000**

```bash
"$PYEXE" "$CLI" components | python -c "import sys,json,pathlib; pathlib.Path('s1.json').write_text(json.dumps(json.load(sys.stdin)['example']))"
"$PYEXE" "$CLI" evaluate 08271000 --structure s1.json --protocol fast --trials 800 \
  | python -c "import sys,json; d=json.load(sys.stdin); print('valid',d['valid'],'nse',d['nse'])"
rm -f s1.json
```
Expected: `valid True nse <finite>` — a clean end-to-end turn on the basin where DeepSeek stalled at 0.0131. (This is a manual sanity run, not an automated assertion.)

- [ ] **Step 3: Full test suite green**

Run: `"$PYEXE" src/hydroagent/scripts/_test_hydro_cli.py`
Expected: `ALL OK (5 test(s))`.

---

## Self-Review (completed by plan author)

**Spec coverage:** §4 architecture → Tasks 1-4. §5.1 components → Task 1. §5.2 basin-info → Task 2. §5.3 evaluate + JSON + exit codes → Tasks 3-4. §6 skill → Task 6. §7 dual protocol → Tasks 1 (config), 4 (fast), 5 (repro). §8 validation/clean-output → Tasks 1 (`_quiet`), 3 (validator), 4 (stdout-only JSON, asserted via `json.loads(r.stdout)`). §9 Claude API seam → Task 7. §10 logging/session → Task 4 (history.jsonl, session dir). §11 testing → Tasks 1-5 smoke + Task 8. §12 honesty caveat → Task 6 skill rules. §13 open items → Task 5 Step 1 (windows), Task 6 Step 1 (skill location), Task 7 (model id). No gaps.

**Placeholder scan:** No TBD/TODO; all code blocks complete; `repro_v01` windows have concrete defaults plus a verify step.

**Type/name consistency:** `_quiet`, `_emit`, `_Done`, `_validate_structure`, `cmd_components`/`cmd_basin_info`/`cmd_evaluate`, `PROTOCOLS`, `_EXAMPLE_STRUCTURE`/`GOOD_STRUCTURE`, `history_path`/`qsim_path` used consistently across tasks. `load_camels_basin(... start_date, end_date, forcing, pet_method)` and `auto_calibrate(forcing, obs, n_trials=)` match the real signatures in `data_loading.py` / `environment.py`.
```
