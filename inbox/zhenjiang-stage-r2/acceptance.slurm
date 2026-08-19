#!/usr/bin/env bash
#SBATCH -J zj_r2_accept
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH -t 00:30:00
#SBATCH -o /data1/home/sunyiq/zhenjiang_stage_direction_r2_20260819/logs/acceptance_%j.out
#SBATCH -e /data1/home/sunyiq/zhenjiang_stage_direction_r2_20260819/logs/acceptance_%j.err

set -o pipefail

ROOT=/data1/home/sunyiq/zhenjiang_stage_direction_r2_20260819
PAYLOAD_ROOT="$ROOT/payload_frozen"
MANIFEST_REL=docs/records/DATONG_STAGE_DIRECTION_EVENT_STABILITY_DIAGNOSTIC_2024_2025_V1_COVERAGE_AUDIT_RETRY_R2_HPC_MIGRATION_MANIFEST.json
MANIFEST="$PAYLOAD_ROOT/$MANIFEST_REL"
TEST_LOG="$ROOT/logs/pytest_acceptance_${SLURM_JOB_ID}.txt"
ACCEPTANCE="$ROOT/migration/hpc_acceptance.json"
EXPECTED_MANIFEST_BYTES=9771
EXPECTED_MANIFEST_SHA=ce3ad6661d8c38c2a4738fff52d15b7ce38316a14ba9e7396cd906b933bc1496

source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || \
source "$HOME/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final || { echo "CONDA_FAILED"; exit 1; }

export CUDA_VISIBLE_DEVICES=-1
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export NUMEXPR_NUM_THREADS=1
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1

mkdir -p "$ROOT/migration" "$ROOT/logs"
cd "$PAYLOAD_ROOT" || exit 1

echo "=== PACKAGE IDENTITY ==="
test -f "$MANIFEST" || { echo "MANIFEST_MISSING"; exit 1; }
test "$(wc -c < "$MANIFEST")" = "$EXPECTED_MANIFEST_BYTES" || { echo "MANIFEST_BYTES_MISMATCH"; exit 1; }
test "$(sha256sum "$MANIFEST" | awk '{print $1}')" = "$EXPECTED_MANIFEST_SHA" || { echo "MANIFEST_SHA_MISMATCH"; exit 1; }

python - "$PAYLOAD_ROOT" "$MANIFEST" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()
manifest_path = Path(sys.argv[2]).resolve()
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
identities = []
for group in manifest["groups"].values():
    identities.extend(group)
assert manifest["source_file_count"] == 30
assert len(identities) == 30
assert len({item["relative_path"] for item in identities}) == 30
expected_files = {item["relative_path"] for item in identities}
expected_files.add(manifest_path.relative_to(root).as_posix())
actual_files = {
    path.relative_to(root).as_posix()
    for path in root.rglob("*")
    if path.is_file()
}
assert actual_files == expected_files, (sorted(expected_files - actual_files), sorted(actual_files - expected_files))
for item in identities:
    path = root / item["relative_path"]
    assert path.stat().st_size == item["bytes"], item["relative_path"]
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    assert digest == item["sha256"], item["relative_path"]
print("PACKAGE_MISMATCH_COUNT=0")
print("PACKAGE_SOURCE_FILE_COUNT=30")
print("PACKAGE_MEMBER_COUNT=31")
PY
PACKAGE_EXIT=$?
if [ "$PACKAGE_EXIT" -ne 0 ]; then
    echo "PACKAGE_VERIFICATION_FAILED exit=$PACKAGE_EXIT"
    exit "$PACKAGE_EXIT"
fi

echo "=== ENVIRONMENT IDENTITY ==="
python - <<'PY'
import hashlib
import os
from pathlib import Path
import sys
import numpy
import pandas
import psutil
import threadpoolctl
import torch

path = Path(sys.executable).resolve()
print(f"interpreter_path={path}")
print(f"interpreter_bytes={path.stat().st_size}")
print(f"interpreter_sha256={hashlib.sha256(path.read_bytes()).hexdigest()}")
print(f"interpreter_version={sys.version}")
print(f"numpy={numpy.__version__}")
print(f"pandas={pandas.__version__}")
print(f"psutil={psutil.__version__}")
print(f"threadpoolctl={threadpoolctl.__version__}")
print(f"torch={torch.__version__}")
print(f"cuda_visible_devices={os.environ.get('CUDA_VISIBLE_DEVICES')}")
print(f"torch_cuda_initialized={torch.cuda.is_initialized()}")
assert os.environ.get("CUDA_VISIBLE_DEVICES") == "-1"
assert torch.cuda.is_initialized() is False
PY
ENV_EXIT=$?
if [ "$ENV_EXIT" -ne 0 ]; then
    echo "ENVIRONMENT_VERIFICATION_FAILED exit=$ENV_EXIT"
    exit "$ENV_EXIT"
fi

echo "=== SYNTHETIC TESTS ==="
python -m pytest -q tests/test_independent_audit_datong_stage_event_stability_v1.py 2>&1 | tee "$TEST_LOG"
TEST_EXIT=${PIPESTATUS[0]}
if [ "$TEST_EXIT" -ne 0 ]; then
    echo "SYNTHETIC_TEST_FAILED exit=$TEST_EXIT"
    exit "$TEST_EXIT"
fi
grep -Eq '(^|[^0-9])64 passed' "$TEST_LOG" || { echo "EXPECTED_64_PASSED_NOT_FOUND"; exit 1; }

python - "$PAYLOAD_ROOT" "$MANIFEST" "$TEST_LOG" "$ACCEPTANCE" "$SLURM_JOB_ID" <<'PY'
import hashlib
import json
from pathlib import Path
import re
import sys
import numpy
import pandas
import psutil
import threadpoolctl
import torch

root = Path(sys.argv[1]).resolve()
manifest_path = Path(sys.argv[2]).resolve()
test_log = Path(sys.argv[3]).resolve()
acceptance_path = Path(sys.argv[4]).resolve()
job_id = sys.argv[5]
text = test_log.read_text(encoding="utf-8")
match = re.search(r"(?:^|\s)(\d+) passed", text)
assert match and int(match.group(1)) == 64
interpreter = Path(sys.executable).resolve()
source_path = root / "scripts/analysis/independent_audit_datong_stage_event_stability_v1.py"
test_path = root / "tests/test_independent_audit_datong_stage_event_stability_v1.py"
payload = {
    "schema_version": 1,
    "migration_id": "datong_stage_direction_r2_hpc_migration_20260819",
    "slurm_job_id": job_id,
    "package_mismatch_count": 0,
    "manifest": {
        "relative_path": manifest_path.relative_to(root).as_posix(),
        "bytes": manifest_path.stat().st_size,
        "sha256": hashlib.sha256(manifest_path.read_bytes()).hexdigest(),
    },
    "interpreter": {
        "path": str(interpreter),
        "bytes": interpreter.stat().st_size,
        "sha256": hashlib.sha256(interpreter.read_bytes()).hexdigest(),
        "version": sys.version,
    },
    "dependencies": {
        "numpy": numpy.__version__,
        "pandas": pandas.__version__,
        "psutil": psutil.__version__,
        "threadpoolctl": threadpoolctl.__version__,
        "torch": torch.__version__,
    },
    "implementation": {
        "relative_path": source_path.relative_to(root).as_posix(),
        "bytes": source_path.stat().st_size,
        "sha256": hashlib.sha256(source_path.read_bytes()).hexdigest(),
    },
    "test": {
        "relative_path": test_path.relative_to(root).as_posix(),
        "bytes": test_path.stat().st_size,
        "sha256": hashlib.sha256(test_path.read_bytes()).hexdigest(),
    },
    "test_evidence": {
        "command": [str(interpreter), "-m", "pytest", "-q", "tests/test_independent_audit_datong_stage_event_stability_v1.py"],
        "test_paths": ["tests/test_independent_audit_datong_stage_event_stability_v1.py"],
        "passed": 64,
        "failed": 0,
        "exit_code": 0,
        "synthetic_only": True,
        "log_path": str(test_log),
        "log_bytes": test_log.stat().st_size,
        "log_sha256": hashlib.sha256(test_log.read_bytes()).hexdigest(),
    },
    "runtime": {
        "device": "cpu",
        "cuda_visible_devices": "-1",
        "torch_cuda_initialized": torch.cuda.is_initialized(),
        "thread_environment": {
            "OMP_NUM_THREADS": "1",
            "MKL_NUM_THREADS": "1",
            "OPENBLAS_NUM_THREADS": "1",
            "NUMEXPR_NUM_THREADS": "1",
        },
    },
}
acceptance_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"acceptance_path={acceptance_path}")
print(f"acceptance_bytes={acceptance_path.stat().st_size}")
print(f"acceptance_sha256={hashlib.sha256(acceptance_path.read_bytes()).hexdigest()}")
PY

echo "=== SLURM IDENTITY ==="
scontrol show job "$SLURM_JOB_ID" || true
echo "ACCEPTANCE_COMPLETED"
