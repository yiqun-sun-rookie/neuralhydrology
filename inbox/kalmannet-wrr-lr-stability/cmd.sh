#!/usr/bin/env bash
set -euo pipefail
/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -I -B - <<'PY'
"""Read-only diagnosis for the single failed learning-rate run: index 2."""
from __future__ import annotations

import hashlib
import json
import math
import subprocess
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path('/data1/home/sunyiq/kalmannet_wrr_lr_stability_20260914')
EXP = ROOT / 'repo/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902'
RUN = EXP / 'runs/formal_seed46_gpu/idx0002_lr0p01_hs32_nl1_mult10'
EXPECTED_MANIFEST = '4f03bd675bd53c5137a37c9cc0af0110052abdc1fa2819a2a5a8226ead0ec4fd'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def text_evidence(path, tail=80):
    if not path.is_file():
        return {'exists': False}
    lines = path.read_text(encoding='utf-8', errors='replace').splitlines()
    needles = ('Traceback', '[Fail]', 'RuntimeError', 'Error', 'exception', 'Exceeded',
               'Grad explosion', 'NaN', 'Inf', 'SafeTrain')
    selected = [{'line': index + 1, 'text': line[:2000]} for index, line in enumerate(lines)
                if any(needle.lower() in line.lower() for needle in needles)]
    return {'exists': True, 'bytes': path.stat().st_size, 'sha256': sha(path),
            'line_count': len(lines), 'selected_last_120': selected[-120:],
            'tail': lines[-tail:]}


def safe(value):
    if isinstance(value, float) and not math.isfinite(value):
        return 'NaN' if math.isnan(value) else ('Infinity' if value > 0 else '-Infinity')
    if isinstance(value, dict):
        return {key: safe(item) for key, item in value.items()}
    if isinstance(value, list):
        return [safe(item) for item in value]
    return value


def main():
    manifest_path = ROOT / 'PACKAGE_MANIFEST.json'
    if sha(manifest_path) != EXPECTED_MANIFEST:
        raise RuntimeError('manifest identity mismatch')
    manifest = json.loads(manifest_path.read_text())
    combo = manifest['combinations'][2]
    if combo != {'index': 2, 'seed': 46, 'effective_seed': 46, 'hidden_size': 32,
                 'num_layers': 1, 'in_out_mult': 10, 'lr': 0.01,
                 'role': 'learning_rate_confirmation', 'run_id': 'WRR-LR-20260914-I02'}:
        raise RuntimeError('failed-run identity mismatch')

    report = {'time_utc': datetime.now(timezone.utc).isoformat(), 'read_only': True,
              'data_tensors_loaded': False, 'checkpoints_loaded': False, 'combo': combo,
              'run_directory_exists': RUN.is_dir()}
    report['scheduler'] = subprocess.run(
        ['sacct', '-X', '-j', '225684_2', '-n', '-P',
         '--format=JobID%40,JobIDRaw,State%40,ExitCode,Start,End,Elapsed,NodeList'],
        capture_output=True, text=True, timeout=30, check=False).__dict__ | {'args': None}
    # Retain only serializable subprocess fields.
    report['scheduler'] = {key: report['scheduler'][key] for key in ('returncode', 'stdout', 'stderr')}

    report['markers'] = {name: (RUN / name).is_file() for name in ('SUCCESS', 'FAILED', 'metrics.json', 'cell_metrics.json', 'error.txt')}
    report['directory_entries'] = []
    if RUN.is_dir():
        for path in sorted(RUN.rglob('*')):
            if path.is_file():
                report['directory_entries'].append({'relative_path': path.relative_to(RUN).as_posix(),
                                                    'bytes': path.stat().st_size})

    report['error'] = text_evidence(RUN / 'error.txt', tail=120)
    report['launcher_log'] = text_evidence(EXP / 'logs/WRR-LR-20260914-I02_formal.stdout.log', tail=100)
    report['slurm_stdout'] = text_evidence(ROOT / 'logs/slurm-225684_2.out', tail=80)
    report['slurm_stderr'] = text_evidence(ROOT / 'logs/slurm-225684_2.err', tail=80)

    epoch_path = RUN / 'results/epoch_log.jsonl'
    epochs = ([json.loads(line) for line in epoch_path.read_text().splitlines() if line.strip()]
              if epoch_path.is_file() else [])
    report['epochs'] = {'count': len(epochs), 'first': epochs[0] if epochs else None,
                        'last': epochs[-1] if epochs else None,
                        'with_recoveries': [record for record in epochs
                                            if record.get('grad_explosion_rollbacks', 0)
                                            or record.get('nan_inf_skips', 0)],
                        'grad_recoveries_total': sum(record.get('grad_explosion_rollbacks', 0) for record in epochs),
                        'loss_recoveries_total': sum(record.get('nan_inf_skips', 0) for record in epochs)}

    observer_path = ROOT / 'diagnostics/index0002.jsonl'
    events = ([json.loads(line) for line in observer_path.read_text().splitlines() if line.strip()]
              if observer_path.is_file() else [])
    recovery_events = [event for event in events if event.get('event') == 'recovery']
    report['observer'] = {'exists': observer_path.is_file(), 'bytes': observer_path.stat().st_size if observer_path.is_file() else None,
                          'sha256': sha(observer_path) if observer_path.is_file() else None,
                          'events': len(events), 'recoveries': len(recovery_events),
                          'recoveries_by_epoch': dict(sorted(Counter(str(event.get('epoch_zero_based')) for event in recovery_events).items())),
                          'first_recovery': recovery_events[0] if recovery_events else None,
                          'last_recovery': recovery_events[-1] if recovery_events else None,
                          'last_events': events[-12:]}
    print(json.dumps(safe(report), sort_keys=True, allow_nan=False), flush=True)


if __name__ == '__main__':
    main()

PY
