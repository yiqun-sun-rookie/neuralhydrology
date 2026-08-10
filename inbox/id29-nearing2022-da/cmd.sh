#!/bin/bash
# ID29 seq=104: on the failing node ngu104, retry the exact server preclosure check with the shared Git package binary.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
PROVENANCE="$ROOT/closure_20260810/provenance"
OUT="$PROVENANCE/shared_git_preclosure_probe_seq104.out"
ERR="$PROVENANCE/shared_git_preclosure_probe_seq104.err"
JOB_RECEIPT="$PROVENANCE/shared_git_preclosure_probe_seq104_job.txt"
SHARED_GIT_DIR="$HOME/miniconda3/pkgs/git-2.55.0-pl5321h5685339_1/bin"
SHARED_GIT="$SHARED_GIT_DIR/git"

echo "=== PRECONDITIONS ==="
test "$(sacct -n -P -j 202370 --format=JobIDRaw,State | awk -F'|' '$1 == "202370" {print $2; exit}')" = "FAILED"
grep -F "FileNotFoundError: [Errno 2] No such file or directory: 'git'" \
  "$ROOT/closure_20260810/logs/N22-preclosure-check_202370.err"
test -x "$SHARED_GIT"
"$SHARED_GIT" --version
test ! -e "$OUT"
test ! -e "$ERR"
test ! -e "$JOB_RECEIPT"

echo "=== TARGETED NGU104 CHECK ==="
set +e
JOB_OUTPUT=$(sbatch --wait --parsable \
  --job-name=N22-preclosure-gitprobe \
  --partition=hgpu2,hgpu4,hgpu8 \
  --nodelist=ngu104 \
  --nodes=1 \
  --ntasks=1 \
  --cpus-per-task=2 \
  --time=00:30:00 \
  --output="$OUT" \
  --error="$ERR" \
  --wrap='set -eo pipefail; ROOT=/data1/home/sunyiq/nearing2022_da; IDEA="$ROOT/src/29_nearing2022_da_ar"; source "$HOME/miniconda3/etc/profile.d/conda.sh"; conda activate nh_final; export PATH="$HOME/miniconda3/pkgs/git-2.55.0-pl5321h5685339_1/bin:$PATH"; cd "$ROOT"; export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"; export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK:-2}"; echo "started=$(date --iso-8601=seconds)"; hostname; command -v git; git --version; python "$IDEA/scripts/run_server_preclosure_check.py" --repo-root "$ROOT" --execution-data-manifest "$ROOT/closure_20260810/provenance/hpc_camels_us_manifest_v2.json"; echo "finished=$(date --iso-8601=seconds)"')
SBATCH_RC=$?
set -e
printf '%s\n' "$JOB_OUTPUT" > "$JOB_RECEIPT"
echo "sbatch_rc=$SBATCH_RC"
echo "job_output=$JOB_OUTPUT"
cat "$OUT"
cat "$ERR"
test "$SBATCH_RC" -eq 0
test ! -s "$ERR"
grep -q '^ngu104$' "$OUT"
grep -Fq "$SHARED_GIT" "$OUT"
grep -q 'git version 2.55.0' "$OUT"
grep -q '"ok": true' "$OUT"
grep -q '"tests": 64' "$OUT"
grep -q '"unique_file_count": 97' "$OUT"
grep -q 'finished=' "$OUT"
sha256sum "$OUT" "$ERR" "$JOB_RECEIPT"

echo "=== SAFETY BOUNDARY ==="
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
test "$(squeue -h -j 202315 -o '%i|%T|%r|%j')" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
