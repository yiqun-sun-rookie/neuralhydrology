#!/usr/bin/env bash
set -eo pipefail
umask 027
ROOT='/data1/home/sunyiq/zhenjiang_5s5t_stage_b_20260907_001'
MAILBOX_ROOT="$(git rev-parse --show-toplevel)"
PAYLOAD="$MAILBOX_ROOT/inbox/zhenjiang-six-source-four-target-ukf/payload_20260907_stage_b_001"
ARCHIVE="$PAYLOAD/zhenjiang_stage_b_code_v2.tar.gz"
MANIFEST="$PAYLOAD/bundle_manifest.json"
fatal() { printf '[FATAL] %s\n' "$1" >&2; exit 1; }
ordinary() { [ -f "$1" ] && [ ! -L "$1" ] || fatal "not ordinary file: $1"; }
identity() { ordinary "$1"; [ "$(stat -c '%s' -- "$1")" = "$2" ] || fatal 'byte count changed'; [ "$(sha256sum -- "$1" | awk '{print $1}')" = "$3" ] || fatal 'SHA-256 changed'; }
[ "$(id -un)" = sunyiq ] || fatal 'unexpected user'
[ ! -e "$ROOT" ] && [ ! -L "$ROOT" ] || fatal 'new root is not absent'
for old in '/data1/home/sunyiq/zhenjiang_six_source_four_target_differentiable_ukf_20260901_r2' '/data1/home/sunyiq/zhenjiang_six_source_four_target_differentiable_ukf_20260902_recovery_attempt_002' '/data1/home/sunyiq/zhenjiang_five_source_five_target_single_analysis_ukf_oracle_datong_20260904_r1' '/data1/home/sunyiq/zhenjiang_5s5t_stage_a_20260905_recovery_001'; do [ -d "$old" ] && [ ! -L "$old" ] || fatal "protected root invalid: $old"; done
identity "$ARCHIVE" '81705' '1b6cab247e8e54994cff7c92d4825dca52aff603ec566602368eed894f2a3a4d'
identity "$MANIFEST" '4572' 'ed5850dd8239a1fe36e3e6ce9b490b65133bd0fc8121809bb787167db75d68ec'
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
export PYTHONDONTWRITEBYTECODE=1
python -B - "$ARCHIVE" "$MANIFEST" <<'PY'
import importlib.util, pathlib, sys, tarfile
archive, manifest = map(pathlib.Path, sys.argv[1:])
with tarfile.open(archive, 'r:gz') as tf:
    names = tf.getnames()
    if names.count('bundle_manifest.json') != 1 or tf.extractfile('bundle_manifest.json').read() != manifest.read_bytes():
        raise SystemExit('inner/outer manifest mismatch')
if importlib.util.find_spec('torch') is None:
    raise SystemExit('nh_final torch distribution is absent; torch is not imported on login')
PY
[ ! -e "$ROOT" ] && [ ! -L "$ROOT" ] || fatal 'new root appeared during preflight'
mkdir -- "$ROOT"
mkdir -p -- "$ROOT/logs" "$ROOT/runs/stage_b" "$ROOT/evidence/stage_b_attempts" "$ROOT/evidence/submission/attempt_001"
tar -xzf "$ARCHIVE" -C "$ROOT" --no-same-owner --no-same-permissions
python -B "$ROOT/run/scripts/hpc/zhenjiang_stage_b_hpc_v2.py" verify-bundle --archive "$ARCHIVE" --manifest "$ROOT/bundle_manifest.json"
for seed in 17 29 43; do
  p="/data1/home/sunyiq/zhenjiang_5s5t_stage_a_20260905_recovery_001/runs/stage_a/seed_${seed}/best_checkpoint.pt"
  case "$seed" in 17) h=374d3278c7e41dee0e2c1e937f936df442a44348a02addd46a2c4bb5b13b8263;; 29) h=7e8a0376f47b3c7f217e004df2519b48dce3311ceb5f3203e1f844eb97c4ff46;; 43) h=79b04446f4407496ceb8f0d85442ac2fe8ecd60db2d64e18c90a0bf3a13fe961;; esac
  identity "$p" 88882 "$h"
done
printf '{"status":"submission_requested","sbatch_call_limit":1}\n' > "$ROOT/evidence/submission/attempt_001/requested.json"
REPLY_FILE="$ROOT/evidence/submission/attempt_001/sbatch_reply.raw.txt"
EXIT_FILE="$ROOT/evidence/submission/attempt_001/sbatch_exit_status.txt"
set +e
sbatch "$ROOT/run/scripts/hpc/zhenjiang_five_source_five_target_stage_b_v2.slurm" 'ed5850dd8239a1fe36e3e6ce9b490b65133bd0fc8121809bb787167db75d68ec' > "$REPLY_FILE" 2>&1
rc=$?
set -e
printf '%s\n' "$rc" > "$EXIT_FILE"
reply="$(cat "$REPLY_FILE")"
printf '%s\n' "$reply"
if [ "$rc" -ne 0 ]; then
  printf '%s\n' 'only authorized sbatch call failed; no retry' > "$ROOT/evidence/submission/attempt_001/submission_failure.txt"
  fatal 'only authorized sbatch call failed; no retry'
fi
if ! job="$(python -B "$ROOT/run/scripts/hpc/zhenjiang_stage_b_hpc_v2.py" parse-submission --text "$reply")"; then
  printf '%s\n' 'submission receipt rejected; no retry' > "$ROOT/evidence/submission/attempt_001/submission_failure.txt"
  fatal 'submission receipt rejected; no retry'
fi
printf '{"status":"submitted","job_id":"%s","sbatch_call_count":1}\n' "$job" > "$ROOT/evidence/submission/attempt_001/submission_receipt.json"
squeue -j "$job" -h -o '%i|%j|%T|%P|%M|%R|%Z' || true
