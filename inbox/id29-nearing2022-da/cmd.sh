#!/bin/bash
# ID29 seq=103: read-only Git executable inventory on login and one compute node after validation job 202370 failed.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
PROVENANCE="$ROOT/closure_20260810/provenance"
OUT="$PROVENANCE/git_executable_compute_probe_seq103.out"
ERR="$PROVENANCE/git_executable_compute_probe_seq103.err"
JOB_RECEIPT="$PROVENANCE/git_executable_compute_probe_seq103_job.txt"

echo "=== FAILED VALIDATION ROOT ==="
test "$(sacct -n -P -j 202370 --format=JobIDRaw,State | awk -F'|' '$1 == "202370" {print $2; exit}')" = "FAILED"
grep -F "FileNotFoundError: [Errno 2] No such file or directory: 'git'" \
  "$ROOT/closure_20260810/logs/N22-preclosure-check_202370.err"

echo "=== LOGIN NODE INVENTORY ==="
hostname
printf 'PATH=%s\n' "$PATH"
command -v git || true
which -a git 2>/dev/null || true
for candidate in /usr/bin/git /bin/git /usr/local/bin/git "$HOME/miniconda3/bin/git" "$HOME/bin/git"; do
  if [ -e "$candidate" ]; then
    ls -l "$candidate"
    "$candidate" --version || true
  else
    echo "missing=$candidate"
  fi
done
find "$HOME/miniconda3" -maxdepth 5 -type f -name git -perm -u+x -print 2>/dev/null | sort || true

echo "=== COMPUTE NODE INVENTORY ==="
test ! -e "$OUT"
test ! -e "$ERR"
test ! -e "$JOB_RECEIPT"
set +e
JOB_OUTPUT=$(sbatch --wait --parsable \
  --job-name=N22-git-probe \
  --partition=hgpu2,hgpu4,hgpu8 \
  --exclude=ngu002 \
  --nodes=1 \
  --ntasks=1 \
  --cpus-per-task=1 \
  --time=00:03:00 \
  --output="$OUT" \
  --error="$ERR" \
  --wrap='set -o pipefail; hostname; printf "PATH=%s\n" "$PATH"; command -v git || true; which -a git 2>/dev/null || true; for candidate in /usr/bin/git /bin/git /usr/local/bin/git "$HOME/miniconda3/bin/git" "$HOME/bin/git"; do if [ -e "$candidate" ]; then ls -l "$candidate"; "$candidate" --version || true; else echo "missing=$candidate"; fi; done; find "$HOME/miniconda3" -maxdepth 5 -type f -name git -perm -u+x -print 2>/dev/null | sort || true; source "$HOME/miniconda3/etc/profile.d/conda.sh"; conda activate nh_final; printf "CONDA_PATH=%s\n" "$PATH"; python -c "import shutil; print(\"python_which_git=\" + str(shutil.which(\"git\")))"')
SBATCH_RC=$?
set -e
printf '%s\n' "$JOB_OUTPUT" > "$JOB_RECEIPT"
echo "sbatch_rc=$SBATCH_RC"
echo "job_output=$JOB_OUTPUT"
cat "$OUT"
cat "$ERR"
test "$SBATCH_RC" -eq 0
test ! -s "$ERR"
sha256sum "$OUT" "$ERR" "$JOB_RECEIPT"

echo "=== SAFETY BOUNDARY ==="
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
test "$(squeue -h -j 202315 -o '%i|%T|%r|%j')" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
