#!/usr/bin/env bash
set -eo pipefail

TARGET=/data1/home/sunyiq/kalmannet_tukf06_20260809/retry1
SOURCE="$TARGET/source"
SCRIPT="$TARGET/benchmarks/bench18.slurm"
OUTPUT="$TARGET/smoke/smoke_09035800.json"

echo "=== BENCHMARK GUARDS ==="
test -d "$SOURCE"
test -f "$SOURCE/bundle_manifest.json"
if [[ -e "$OUTPUT" ]]; then
  echo "18-state benchmark output already exists; refusing overwrite" >&2
  exit 41
fi
if squeue -u "$USER" -h -n tukf06-bench18 -o '%i' | grep -q .; then
  echo "an existing tukf06-bench18 job is queued or running" >&2
  exit 42
fi
mkdir -p "$TARGET/benchmarks"
if [[ -e "$SCRIPT" ]]; then
  echo "18-state benchmark script already exists; refusing overwrite" >&2
  exit 43
fi

cat > "$SCRIPT" <<'SLURM'
#!/usr/bin/env bash
#SBATCH -J tukf06-bench18
#SBATCH -p hcpu48
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=48
#SBATCH -t 00:30:00
#SBATCH -o /data1/home/sunyiq/kalmannet_tukf06_20260809/retry1/logs/bench18-%j.out
#SBATCH -e /data1/home/sunyiq/kalmannet_tukf06_20260809/retry1/logs/bench18-%j.err

set -eo pipefail
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || source "$HOME/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export NUMEXPR_NUM_THREADS=1
ROOT=/data1/home/sunyiq/kalmannet_tukf06_20260809/retry1
cd "$ROOT/source"
bash hpc/tukf06_full_diagonal/preflight.sh
python -u scripts/smoke_tukf06_full_diagonal.py \
  --config configs/tukf06_full_diagonal_search_head_to_head_v1.json \
  --search-design configs/tukf06_search_design_v1.npz \
  --data-root /data1/home/sunyiq/neuralhydrology/data/camels_us \
  --prior-csv inputs/hbv_lite_cma_local_full.csv \
  --basin-list inputs/conceptual_benchmark_camels_us_531_repro.txt \
  --loader-file vendor/hydroagent_data_loading.py \
  --basin 09035800 \
  --output "$ROOT/smoke/smoke_09035800.json"
scontrol show job "$SLURM_JOB_ID"
SLURM
chmod 700 "$SCRIPT"
echo "benchmark_script_sha256=$(sha256sum "$SCRIPT" | awk '{print $1}')"

echo "=== SUBMIT PAID 18-STATE BENCHMARK ==="
JID=$(sbatch --parsable "$SCRIPT")
echo "jobid=$JID"
printf '%s\n' "$JID" > "$TARGET/benchmarks/bench18_job_id.txt"

echo "=== WAIT FOR THIS JOB ONLY ==="
for i in $(seq 1 180); do
  if ! squeue -h -j "$JID" -o '%i' 2>/dev/null | grep -q .; then
    break
  fi
  if [[ $((i % 6)) -eq 0 ]]; then
    echo "elapsed_wait_seconds=$((i * 10))"
    squeue -h -j "$JID" -o '%.18i %.24j %.10P %.8T %.10M %.20R'
  fi
  sleep 10
done

echo "=== ACCOUNTING ==="
sacct -j "$JID" -X --format=JobID%12,JobName%18,Partition%10,NodeList%12,State%18,ExitCode%8,Elapsed%10,TotalCPU%12,MaxRSS%12
echo "=== STDOUT ==="
tail -120 "$TARGET/logs/bench18-${JID}.out" 2>/dev/null || true
echo "=== STDERR ==="
tail -120 "$TARGET/logs/bench18-${JID}.err" 2>/dev/null || true
echo "=== BENCHMARK JSON ==="
if [[ ! -f "$OUTPUT" ]]; then
  echo "18-state benchmark result is absent" >&2
  exit 44
fi
cat "$OUTPUT"
