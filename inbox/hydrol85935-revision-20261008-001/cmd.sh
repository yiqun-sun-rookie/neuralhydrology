#!/usr/bin/env bash
set -eo pipefail
ROOT=/data1/home/sunyiq/hydrol85935_revision_20261008_001
PAYLOAD="$HOME/hpc_mailbox/inbox/hydrol85935-revision-20261008-001/payload/diagnose_backend.py"
test "$(cat "$ROOT/OWNER")" = hydrol85935_revision_20261008_001
printf '%s  %s\n' 'f27e980077b20443034907dbabdacc116c19a6284190fd15b909b0b95fd16f5c' "$PAYLOAD" | sha256sum -c -
test ! -e "$ROOT/control/backend_v002.sbatch"
cat > "$ROOT/control/backend_v002.sbatch" <<'JOB'
#!/usr/bin/env bash
#SBATCH -J hydrol85935-backend
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --exclude=ngu002
#SBATCH -t 00:20:00
#SBATCH --no-requeue
#SBATCH -o /data1/home/sunyiq/hydrol85935_revision_20261008_001/logs/backend-%j.out
#SBATCH -e /data1/home/sunyiq/hydrol85935_revision_20261008_001/logs/backend-%j.err
set -eo pipefail
ROOT=/data1/home/sunyiq/hydrol85935_revision_20261008_001
export TMPDIR="$ROOT/tmp/backend-$SLURM_JOB_ID"
mkdir -p "$TMPDIR"
test "$(readlink -f "$TMPDIR")" = "$TMPDIR"
export TMP="$TMPDIR" TEMP="$TMPDIR" XDG_CACHE_HOME="$TMPDIR/cache" MPLCONFIGDIR="$TMPDIR/matplotlib"
export PYTHONDONTWRITEBYTECODE=1 MKL_THREADING_LAYER=GNU MKL_SERVICE_FORCE_INTEL=1 OMP_NUM_THREADS=4 OPENBLAS_NUM_THREADS=4
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
python -u "$HOME/hpc_mailbox/inbox/hydrol85935-revision-20261008-001/payload/diagnose_backend.py"
JOB
test ! -e "$ROOT/control/backend_v002_submission_attempt"
date -Is > "$ROOT/control/backend_v002_submission_attempt"
set +e
out=$(sbatch "$ROOT/control/backend_v002.sbatch" 2>&1)
status=$?
set -e
printf '%s\n' "$out" | tee "$ROOT/control/backend_v002_submission.txt"
test "$status" -eq 0
printf '%s\n' "$out" | grep -qE '^Submitted batch job [0-9]+$'
job=$(printf '%s\n' "$out" | sed -n 's/^Submitted batch job \([0-9][0-9]*\)$/\1/p')
printf '%s\n' "$job" > "$ROOT/control/backend_v002_job_id"
squeue -j "$job" -o '%.18i %.12P %.30j %.10T %.12M %.30R'
