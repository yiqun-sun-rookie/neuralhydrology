#!/usr/bin/env bash
set -eo pipefail
ROOT=/data1/home/sunyiq/hydrol85935_revision_20261008_001
PAYLOAD="$HOME/hpc_mailbox/inbox/hydrol85935-revision-20261008-001/payload/input_compare_v002.tar.gz"
test "$(cat "$ROOT/OWNER")" = hydrol85935_revision_20261008_001
printf '%s  %s\n' '4b872ed6403f8f99bd9e20ce28b4922511c3efb5fa3c2df4d32c73b586230798' "$PAYLOAD" | sha256sum -c -
mkdir "$ROOT/control/input_compare"
tar -xzf "$PAYLOAD" -C "$ROOT/control/input_compare"
test ! -e "$ROOT/control/input_compare_v002.sbatch"
cat > "$ROOT/control/input_compare_v002.sbatch" <<'JOB'
#!/usr/bin/env bash
#SBATCH -J hydrol85935-inputcompare
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --exclude=ngu002
#SBATCH -t 00:20:00
#SBATCH --no-requeue
#SBATCH -o /data1/home/sunyiq/hydrol85935_revision_20261008_001/logs/inputcompare-%j.out
#SBATCH -e /data1/home/sunyiq/hydrol85935_revision_20261008_001/logs/inputcompare-%j.err
set -eo pipefail
ROOT=/data1/home/sunyiq/hydrol85935_revision_20261008_001
export TMPDIR="$ROOT/tmp/inputcompare-$SLURM_JOB_ID"
mkdir -p "$TMPDIR"
test "$(readlink -f "$TMPDIR")" = "$TMPDIR"
export TMP="$TMPDIR" TEMP="$TMPDIR" XDG_CACHE_HOME="$TMPDIR/cache" MPLCONFIGDIR="$TMPDIR/matplotlib"
export PYTHONDONTWRITEBYTECODE=1 MKL_THREADING_LAYER=GNU MKL_SERVICE_FORCE_INTEL=1 OMP_NUM_THREADS=4 OPENBLAS_NUM_THREADS=4
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
python -u "$ROOT/control/input_compare/compare_remote_inputs.py"
JOB
test ! -e "$ROOT/control/input_compare_v002_submission_attempt"
date -Is > "$ROOT/control/input_compare_v002_submission_attempt"
set +e
out=$(sbatch "$ROOT/control/input_compare_v002.sbatch" 2>&1)
status=$?
set -e
printf '%s\n' "$out" | tee "$ROOT/control/input_compare_v002_submission.txt"
test "$status" -eq 0
printf '%s\n' "$out" | grep -qE '^Submitted batch job [0-9]+$'
job=$(printf '%s\n' "$out" | sed -n 's/^Submitted batch job \([0-9][0-9]*\)$/\1/p')
printf '%s\n' "$job" > "$ROOT/control/input_compare_v002_job_id"
squeue -j "$job" -o '%.18i %.12P %.30j %.10T %.12M %.30R'
