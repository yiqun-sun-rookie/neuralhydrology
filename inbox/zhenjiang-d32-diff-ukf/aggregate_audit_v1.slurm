#!/bin/bash
#SBATCH --job-name=zhd32_dukf_aggregate
#SBATCH --partition=hcpu48,hcpu48y
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --exclude=ngu002
#SBATCH --time=01:00:00
#SBATCH --output=/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_dev_eval_20260831_r3/logs/aggregate_audit_%j.out
#SBATCH --error=/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_dev_eval_20260831_r3/logs/aggregate_audit_%j.err

set -euo pipefail

EVALUATION_ROOT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_dev_eval_20260831_r3"
TRAINING_ROOT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_20260828_r2"
RUN_ROOT="${EVALUATION_ROOT}/run"
WORKERS_ROOT="${EVALUATION_ROOT}/workers"
SUMMARY_ROOT="${EVALUATION_ROOT}/summary"
SUMMARY_ATTEMPT="${SUMMARY_ROOT}/ZHD32-DUKF-DEV-EVAL-SUMMARY-V1/attempt_001"
AUDIT_ATTEMPT="${EVALUATION_ROOT}/audit/ZHD32-DUKF-DEV-EVAL-SUMMARY-V1/attempt_001"
AUDIT_PARTIAL="${AUDIT_ATTEMPT}.partial"
REGISTRY="${RUN_ROOT}/docs/records/ZHENJIANG_D32_GRU_DIFFERENTIABLE_UKF_V1_DEVELOPMENT_EVALUATION_REGISTRY_R3.json"
EVALUATOR="${RUN_ROOT}/scripts/analysis/zhenjiang_d32_gru_differentiable_ukf_development_evaluation_v1.py"
AUDITOR="${RUN_ROOT}/scripts/analysis/audit_zhenjiang_d32_gru_differentiable_ukf_development_evaluation_v1.py"

export EVALUATION_ROOT TRAINING_ROOT RUN_ROOT WORKERS_ROOT SUMMARY_ROOT
export SUMMARY_ATTEMPT AUDIT_ATTEMPT AUDIT_PARTIAL REGISTRY EVALUATOR AUDITOR
export PYTHONDONTWRITEBYTECODE=1
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK:-4}"

require_directory() {
  if [ ! -d "$1" ]; then
    echo "required directory is absent: $1" >&2
    exit 2
  fi
}

require_file() {
  if [ ! -f "$1" ] || [ -L "$1" ]; then
    echo "required regular non-symbolic file is absent: $1" >&2
    exit 2
  fi
}

echo "aggregate_audit_started=$(date -Is)"
echo "scheduler_job_id=${SLURM_JOB_ID:-absent}"
echo "scheduler_node=$(hostname -s)"
if [ "$(hostname -s)" = "ngu002" ]; then
  echo "forbidden node ngu002 was allocated" >&2
  exit 2
fi

require_directory "${EVALUATION_ROOT}"
require_directory "${RUN_ROOT}"
require_directory "${WORKERS_ROOT}"
require_file "${REGISTRY}"
require_file "${EVALUATOR}"
require_file "${AUDITOR}"
if [ -e "${SUMMARY_ATTEMPT}" ] || [ -e "${SUMMARY_ATTEMPT}.partial" ]; then
  echo "summary output already exists" >&2
  exit 2
fi
if [ -e "${AUDIT_ATTEMPT}" ] || [ -e "${AUDIT_PARTIAL}" ]; then
  echo "audit output already exists" >&2
  exit 2
fi

source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final
cd "${RUN_ROOT}"
export PYTHONPATH="${TRAINING_ROOT}/run/scripts/modeling:${RUN_ROOT}/scripts/analysis:${TRAINING_ROOT}/run/scripts/astronomical_tide:${TRAINING_ROOT}/run/third_party:${PYTHONPATH:-}"

for SEED in 17 29 43; do
  WORKER="${WORKERS_ROOT}/ZHD32-DUKF-DEV-EVAL-S${SEED}-V1/attempt_001"
  require_directory "${WORKER}"
  if [ -e "${WORKER}.partial" ]; then
    echo "worker partial output exists for seed ${SEED}" >&2
    exit 2
  fi
  python -u "${EVALUATOR}" --verify-output "${WORKER}"
done

/usr/bin/time -v python -u "${EVALUATOR}" \
  --aggregate \
  --registry "${REGISTRY}" \
  --workers-root "${WORKERS_ROOT}" \
  --output-root "${SUMMARY_ROOT}"

python - "${SUMMARY_ATTEMPT}" <<'PY'
import json
import sys
from pathlib import Path

from zhenjiang_d32_gru_differentiable_ukf_development_evaluation_v1 import (
    verify_summary_output,
)

result = verify_summary_output(Path(sys.argv[1]))
print(json.dumps(result, indent=2, sort_keys=True))
PY

mkdir -p "$(dirname "${AUDIT_ATTEMPT}")"
mkdir "${AUDIT_PARTIAL}"
/usr/bin/time -v python -u "${AUDITOR}" \
  --summary "${SUMMARY_ATTEMPT}" \
  --workers-root "${WORKERS_ROOT}" \
  > "${AUDIT_PARTIAL}/independent_audit.json"

python - "${AUDIT_PARTIAL}/independent_audit.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
result = json.loads(path.read_text())
allowed_machine_statuses = {
    "pass_2023_development_candidate_for_test_contract",
    "fail_2023_primary_gate_stop_current_family",
}
if result.get("status") != "reproducible":
    raise SystemExit("independent audit reproducibility gate failed")
if result.get("machine_status") not in allowed_machine_statuses:
    raise SystemExit("independent audit machine status is invalid")
if result.get("worker_count") != 3:
    raise SystemExit("independent audit worker count changed")
if result.get("bootstrap_repeat_count") != 20000:
    raise SystemExit("independent audit bootstrap repeat count changed")
if result.get("bootstrap_seed") != 20260828:
    raise SystemExit("independent audit bootstrap seed changed")
if result.get("primary_condition_seed_count") != 18:
    raise SystemExit("independent audit primary condition coverage changed")
print(
    "independent_audit_gate=pass machine_status=%s"
    % result["machine_status"]
)
PY

mv "${AUDIT_PARTIAL}" "${AUDIT_ATTEMPT}"

python - "${SUMMARY_ATTEMPT}" <<'PY'
import json
import sys
from pathlib import Path

from zhenjiang_d32_gru_differentiable_ukf_development_evaluation_v1 import (
    verify_summary_output,
)

result = verify_summary_output(Path(sys.argv[1]))
print(json.dumps(result, indent=2, sort_keys=True))
PY

sha256sum \
  "${SUMMARY_ATTEMPT}/completion_manifest.json" \
  "${SUMMARY_ATTEMPT}/development_gate.json" \
  "${SUMMARY_ATTEMPT}/bootstrap_condition_summary.csv" \
  "${AUDIT_ATTEMPT}/independent_audit.json"
echo "aggregate_audit_completed=$(date -Is)"
