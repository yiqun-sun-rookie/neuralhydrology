#!/usr/bin/env bash
# Read only the completed, registered pilot. No scheduler mutation or rerun.
set -eo pipefail
exec /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
from pathlib import Path
from datetime import datetime, timezone
import base64
import gzip
import hashlib
import io
import json
import subprocess
import tarfile

root = Path('/data1/home/sunyiq/precip_dynamic_filter_20260930/run_20261001_222234_hpc_repair1_d27632e6')
assert root.resolve() == root
assert (root / 'submission_receipt.txt').read_text().strip() == '235201'
complete = json.loads((root / 'pilot/complete.json').read_text())
assert complete == {'stage': 'all', 'success': True, 'automatic_expansion': False}
assert not (root / 'pilot/failure.json').exists()

def safe(path):
    assert path.is_file() and not path.is_symlink()
    assert path.resolve().is_relative_to(root)
    return path

def digest(path):
    sha = hashlib.sha256()
    with safe(path).open('rb') as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b''):
            sha.update(chunk)
    return sha.hexdigest()

accounting = subprocess.check_output([
    'sacct', '-X', '-n', '-P', '-S', '2026-10-01', '-j', '235201',
    '--format=JobID,State,ExitCode,ElapsedRaw,Submit,Start,End,Partition,AllocCPUS,NodeList'
], text=True)
accounting_lines = [line.strip() for line in accounting.splitlines() if line.strip()]
assert len(accounting_lines) == 1
fields = accounting_lines[0].split('|')
assert fields[:3] == ['235201', 'COMPLETED', '0:0']
bundle = json.loads((root / 'bundle_manifest.json').read_text())
snapshot_checks = {name: digest(root / name) == expected for name, expected in bundle['files'].items()}
assert all(snapshot_checks.values())

files = [root / name for name in (
    'submission_receipt.txt', 'bundle_manifest.json',
    'logs/pilot-235201.out', 'logs/pilot-235201.err',
    'synthetic/technical_gate.json', 'synthetic/tests.xml', 'synthetic/tests_stdout.txt',
    'probe/probe_gate.json', 'pilot/run_manifest.json', 'pilot/selection_locked.json',
    'pilot/summary.json', 'pilot/complete.json',
    'code/src/precip_input_assimilation/configs/dynamic_filter_pilot_v03.yml'
)]
files += sorted((root / 'pilot/fits').rglob('fit_summary.json'))
files += sorted((root / 'pilot/fits').rglob('selected.pt'))
files += sorted((root / 'pilot/fits').rglob('epoch_*.json'))
files += sorted((root / 'pilot/scoring').glob('*/predictions.csv'))
files += sorted((root / 'pilot/scoring').glob('*/diagnostics.json'))
assert len(list((root / 'pilot/fits').rglob('fit_summary.json'))) == 27
assert len(list((root / 'pilot/fits').rglob('selected.pt'))) == 27
assert len(list((root / 'pilot/scoring').glob('*/predictions.csv'))) == 11
assert len(list((root / 'pilot/scoring').glob('*/diagnostics.json'))) == 11
files = sorted(set(files))
assert sum(safe(path).stat().st_size for path in files) < 256 * 1024 * 1024
rain_files = sorted((root / 'pilot/scoring').glob('*/rain_versions.csv'))
assert len(rain_files) == 6

file_manifest = {path.relative_to(root).as_posix(): {
    'bytes': path.stat().st_size, 'mtime_ns': path.stat().st_mtime_ns, 'sha256': digest(path)
} for path in files}
rain_manifest = {path.relative_to(root).as_posix(): {
    'bytes': path.stat().st_size, 'mtime_ns': path.stat().st_mtime_ns, 'sha256': digest(path),
    'transfer_status': 'original retained on HPC; digest and diagnostics included'
} for path in rain_files}
collection = {
    'collected_at_utc': datetime.now(timezone.utc).isoformat(), 'job': 235201,
    'root': root.as_posix(), 'accounting': accounting_lines,
    'prior_failed_gpu_seconds': bundle['prior_gpu_seconds'],
    'current_elapsed_seconds': int(fields[3]),
    'total_this_network_gpu_seconds': int(fields[3]) + bundle['prior_gpu_seconds'],
    'old_multiplier_gpu_seconds_separate': 5312,
    'frozen_snapshot_files_verified': len(snapshot_checks),
    'files': file_manifest, 'rain_version_originals': rain_manifest,
    'scope': 'Read-only artifact export; no training, scoring, new data access, or scheduler changes.'
}
stream = io.BytesIO()
with tarfile.open(fileobj=stream, mode='w') as archive:
    for path in files:
        name = path.relative_to(root).as_posix()
        raw = safe(path).read_bytes()
        assert hashlib.sha256(raw).hexdigest() == file_manifest[name]['sha256']
        info = tarfile.TarInfo(name)
        info.size, info.mtime, info.mode = len(raw), 0, 0o444
        archive.addfile(info, io.BytesIO(raw))
    raw = json.dumps(collection, indent=2, ensure_ascii=False).encode()
    info = tarfile.TarInfo('collection_manifest.json')
    info.size, info.mtime, info.mode = len(raw), 0, 0o444
    archive.addfile(info, io.BytesIO(raw))
payload = gzip.compress(stream.getvalue(), compresslevel=3, mtime=0)
assert len(payload) < 12 * 1024 * 1024, 'Transfer exceeds bounded receipt size; preserve files and split export.'
print('TRANSFER_JSON=' + json.dumps({
    'bytes': len(payload), 'sha256': hashlib.sha256(payload).hexdigest(),
    'files': len(file_manifest), 'rain_original_bytes': sum(v['bytes'] for v in rain_manifest.values()),
    'collection_time_utc': collection['collected_at_utc']
}))
print('ARCHIVE_BASE64_BEGIN')
print(base64.b64encode(payload).decode())
print('ARCHIVE_BASE64_END')
print('READ_ONLY_EXPORT_COMPLETE')
PY
