#!/usr/bin/env bash
set -euo pipefail
/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -I -B - <<'PY'
"""Read-only, metadata-only observation of this ten-run deployment."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import math
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path('/data1/home/sunyiq/kalmannet_wrr_lr_stability_20260914')
EXP = ROOT / 'repo/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902'


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8')) if path.is_file() else None


def run_command(arguments):
    result = subprocess.run(arguments, capture_output=True, text=True, timeout=30, check=False)
    return {'returncode': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr}


def json_safe(value):
    """Preserve non-finite diagnostic values explicitly without emitting invalid JSON."""
    if isinstance(value, float) and not math.isfinite(value):
        if math.isnan(value):
            return 'NaN'
        return 'Infinity' if value > 0 else '-Infinity'
    if isinstance(value, dict):
        return {key: json_safe(item) for key, item in value.items()}
    if isinstance(value, list):
        return [json_safe(item) for item in value]
    return value


def main():
    report = {'time_utc': datetime.now(timezone.utc).isoformat(), 'root': str(ROOT),
              'root_exists': ROOT.is_dir(), 'read_only': True, 'data_tensors_loaded': False}
    if not ROOT.is_dir():
        print(json.dumps(report, sort_keys=True))
        return
    manifest_raw = (ROOT / 'PACKAGE_MANIFEST.json').read_bytes()
    if hashlib.sha256(manifest_raw).hexdigest() != '4f03bd675bd53c5137a37c9cc0af0110052abdc1fa2819a2a5a8226ead0ec4fd':
        raise RuntimeError('frozen package manifest mismatch')
    manifest = json.loads(manifest_raw)
    if manifest['remote_root'] != str(ROOT) or manifest['allowed_indices'] != list(range(10)):
        raise RuntimeError('observer deployment identity mismatch')
    # Code and metadata hashes only. Never read any dataset/checkpoint tensor file.
    mismatch = []
    for name, digest in manifest['static_files'].items():
        path = ROOT / name
        if (not path.is_file() or path.is_symlink()
                or not path.resolve().is_relative_to(ROOT.resolve())
                or hashlib.sha256(path.read_bytes()).hexdigest() != digest):
            mismatch.append(name)
    report['static_mismatches'] = mismatch
    report['static_files_checked'] = len(manifest['static_files'])
    if mismatch:
        print(json.dumps(report, sort_keys=True))
        raise RuntimeError('frozen static file mismatch')
    job_file = ROOT / 'array_job_id.txt'
    job_id = job_file.read_text().strip() if job_file.is_file() else None
    report['job_id'] = job_id
    report['deployment_receipt'] = read_json(ROOT / 'DEPLOYMENT_RECEIPT.json')
    report['submission_response'] = read_json(ROOT / 'SUBMISSION_RESPONSE.json')
    if job_id:
        if not job_id.isdigit():
            raise RuntimeError('invalid recorded job id')
        report['squeue'] = run_command(['squeue', '-j', job_id, '-o', '%i|%j|%T|%P|%M|%R'])
        report['sacct'] = run_command(['sacct', '-X', '-j', job_id, '-n', '-P',
                                      '--format=JobID%40,JobIDRaw,State%40,ExitCode,Start,End,Elapsed,AllocTRES'])
    spec = importlib.util.spec_from_file_location('frozen_lr_metadata_analysis', ROOT / 'analyze.py')
    analysis = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(analysis)
    report['runs'] = []
    for combo in manifest['combinations']:
        index, seed, lr = combo['index'], combo['seed'], combo['lr']
        run_dir = EXP / f'runs/formal_seed{seed}_gpu/idx{index:04d}_lr{str(lr).replace(".", "p")}_hs32_nl1_mult10'
        record = {'index': index, 'seed': seed, 'lr': lr, 'run_id': combo['run_id'],
                  'claim': read_json(ROOT / f'claims/index{index:04d}.json'),
                  'run_directory_exists': run_dir.is_dir()}
        audits = sorted((EXP / 'audits').glob(f'{combo["run_id"]}_formal_*.json'))
        if len(audits) > 1:
            raise RuntimeError(f'multiple launch audits for index {index}')
        audit = read_json(audits[0]) if audits else None
        if audit:
            inner = read_json(EXP / 'source_manifest.json')
            record['audit'] = {key: audit.get(key) for key in (
                'run_id', 'mode', 'started_at', 'finished_at', 'combo', 'runtime',
                'launcher_status', 'slurm_job_id', 'slurm_array_task_id', 'hostname',
                'verified_data', 'held_out_test_loaded')}
            record['audit']['source_manifest_matches'] = audit['verified_source'] == inner['source_sha256']
            record['audit']['combo_matches'] = audit['combo'] == combo
        else:
            record['audit'] = None
        epoch_path = run_dir / 'results/epoch_log.jsonl'
        epochs = []
        if epoch_path.is_file():
            epochs = [json.loads(line) for line in epoch_path.read_text().splitlines() if line.strip()]
        record['completed_epoch_records'] = len(epochs)
        record['last_epoch'] = epochs[-1] if epochs else None
        record['cell_metrics'] = read_json(run_dir / 'cell_metrics.json')
        events_path = ROOT / f'diagnostics/index{index:04d}.jsonl'
        if events_path.is_file():
            raw = events_path.read_bytes()
            lines = raw.splitlines(keepends=True)
            incomplete = bool(lines and not lines[-1].endswith(b'\n'))
            if incomplete:
                lines = lines[:-1]
            events = [json.loads(line) for line in lines]
            record['observer_partial_last_line'] = incomplete
            record['stability'] = analysis.summarize_events(events)
            # Full trajectories stay on disk; compact progress does not duplicate them.
            changes = record['stability'].pop('learning_rate_changes_at_batch_start')
            record['learning_rate_change_count'] = len(changes)
            record['last_batch_learning_rates'] = changes[-1] if changes else None
            if record['cell_metrics']:
                best = record['cell_metrics']['validation_scoring']['best_epoch_zero_based']
                record['stability_through_best_epoch'] = analysis.summarize_events(events, best)
        report['runs'].append(record)
    print(json.dumps(json_safe(report), sort_keys=True, allow_nan=False), flush=True)


if __name__ == '__main__':
    main()

PY
