#!/usr/bin/env bash
# Read the submission wrapper and its invocation context; never execute it.
set -e -o pipefail
export PYTHONDONTWRITEBYTECODE=1
export PYTHONNOUSERSITE=1
export ZJ_WRAPPER_READONLY_SBATCH_KIND="$(builtin type -t sbatch || true)"
export ZJ_WRAPPER_READONLY_SBATCH_PATH="$(builtin type -P sbatch || true)"
export ZJ_WRAPPER_READONLY_SBATCH_ALIAS="$(builtin alias sbatch 2>/dev/null || true)"
export ZJ_WRAPPER_READONLY_XBATCH_KIND="$(builtin type -t xbatch || true)"
export ZJ_WRAPPER_READONLY_XBATCH_PATH="$(builtin type -P xbatch || true)"
export ZJ_WRAPPER_READONLY_BASH_VERSION="$BASH_VERSION"
if builtin shopt -q expand_aliases; then
    export ZJ_WRAPPER_READONLY_ALIAS_EXPANSION=enabled
else
    export ZJ_WRAPPER_READONLY_ALIAS_EXPANSION=disabled
fi
python3 -B - <<'PY'
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import stat

WRAPPER = Path('/usr/local/globle/softs/slurm/19.05.4.1/bin/xbatch')
SIBLING_SUBMITTER = Path('/usr/local/globle/softs/slurm/19.05.4.1/bin/sbatch')
FAILED_SCRIPT = Path('/data1/home/sunyiq/zhenjiang_matched_legacy_process_20260907_001/hpc/matched_legacy.slurm')
PROFILES = [Path('/etc/profile'), Path('/etc/bashrc'),
            Path('/data1/home/sunyiq/.bash_profile'), Path('/data1/home/sunyiq/.bashrc')]
MAX_BYTES = 262144

def utc_now():
    return datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')

def sanitize(line):
    if re.search(r'(?i)(password|passwd|token|secret|credential|authorization|api[_-]?key)\s*[=:]', line):
        return '[REDACTED potentially sensitive assignment]'
    if re.search(r'(?i)Bearer\s+\S+|https?://[^/\s:@]+:[^@\s]+@', line):
        return '[REDACTED potentially sensitive authentication text]'
    return line

def inspect(path, content_kind):
    result = {'path': str(path)}
    try:
        info = path.lstat()
        result.update(byte_count=info.st_size, mode=oct(stat.S_IMODE(info.st_mode)),
                      owner_uid=info.st_uid, owner_gid=info.st_gid,
                      modified_at_utc=datetime.fromtimestamp(info.st_mtime, timezone.utc).isoformat(),
                      executable=os.access(path, os.X_OK))
        if stat.S_ISLNK(info.st_mode):
            result.update(status='symlink_metadata_only', link_target=sanitize(os.readlink(path)))
            return result
        if not stat.S_ISREG(info.st_mode):
            result['status'] = 'not_regular_metadata_only'
            return result
        if content_kind == 'metadata_only' or info.st_size > MAX_BYTES:
            result['status'] = 'metadata_only'
            return result
        with path.open('rb') as handle:
            raw = handle.read(MAX_BYTES + 1)
        if len(raw) > MAX_BYTES:
            result['status'] = 'grew_beyond_bound_no_content_returned'
            return result
        result.update(status='read', bytes_read=len(raw), sha256=hashlib.sha256(raw).hexdigest(),
                      magic_prefix_hex=raw[:16].hex())
        if b'\x00' in raw:
            result['content_format'] = 'binary'
            return result
        decoded = raw.decode('utf-8', errors='replace')
        lines = decoded.splitlines()
        result['content_format'] = 'text'
        result['total_line_count'] = len(lines)
        result['lines'] = [{'line_number': index, 'text': sanitize(line)}
            for index, line in enumerate(lines, 1)
            if content_kind == 'full_source' or re.search(r'(?i)sbatch|xbatch|slurm', line)]
    except FileNotFoundError:
        result['status'] = 'absent'
    except Exception as error:
        result.update(status='unavailable', error_type=type(error).__name__)
    return result

report = {'schema_version': 1, 'kind': 'read_only_submission_wrapper_inspection',
          'observed_at_utc': utc_now(), 'submission_program_calls': 0,
          'scheduler_mutations': 0, 'formal_data_reads': 0, 'checkpoint_reads': 0,
          'experiment_filesystem_writes': 0,
          'context': {key: sanitize(os.environ.get(key, '')) for key in (
              'ZJ_WRAPPER_READONLY_SBATCH_KIND', 'ZJ_WRAPPER_READONLY_SBATCH_PATH',
              'ZJ_WRAPPER_READONLY_SBATCH_ALIAS', 'ZJ_WRAPPER_READONLY_XBATCH_KIND',
              'ZJ_WRAPPER_READONLY_XBATCH_PATH', 'ZJ_WRAPPER_READONLY_BASH_VERSION',
              'ZJ_WRAPPER_READONLY_ALIAS_EXPANSION', 'PATH', 'CONDA_PREFIX', 'BASH_ENV')},
          'wrapper': inspect(WRAPPER, 'full_source'),
          'sibling_submitter': inspect(SIBLING_SUBMITTER, 'metadata_only'),
          'failed_submission_script': inspect(FAILED_SCRIPT, 'full_source'),
          'profile_submission_lines': [inspect(path, 'matching_lines') for path in PROFILES]}
report['finished_at_utc'] = utc_now()
print('READ_ONLY_SUBMISSION_WRAPPER_INSPECTION')
print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
PY
