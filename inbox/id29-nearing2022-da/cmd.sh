set -o pipefail
# READ-ONLY (seq 736): export deployed warmpair runner bytes + basedataset hash
ROOT=/data1/home/sunyiq/nearing2022_da
R="$ROOT/src/29_nearing2022_da_ar/hpc/run_warmup_target_pair.slurm"
sha256sum "$R" "$ROOT/neuralhydrology/datasetzoo/basedataset.py"
echo "=== RUNNER_B64_BEGIN ==="
base64 -w0 "$R"; echo
echo "=== RUNNER_B64_END ==="
exit 0
