#!/bin/bash
# precip-input-da seq=1 (2026-09-19): stage 0b-1 of
#   docs/plans/2026-09-19-precip-input-assimilation-plan-v1-decisive-trial.md
# READ-ONLY on the ID33 landing. Creates the new landing, COPIES (never moves) the three C4 checkpoints, extracts the
# seed-100 TUNING-YEAR validation sim/obs (2006-10-01..2007-09-30 only; the exam year stays on the cluster) and a
# 4-basin slice of the track0 Maurer parquet, and ships them back as base64 tar.gz between the markers.
# No sbatch. No compute beyond a single-thread python of a few seconds. No backslash literals in this file.
set -eo pipefail
export MKL_THREADING_LAYER=GNU MKL_SERVICE_FORCE_INTEL=1 OMP_NUM_THREADS=1 MKL_NUM_THREADS=1
SRC=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
DST=/data1/home/sunyiq/precip_input_da_2026_09
HELPER="$HOME/hpc_mailbox/inbox/precip-input-da/payload/extract_0b1.py"
PARQ="$SRC/data/camels_us_track0_development_forcing_v01/track0_forcing.parquet"
date "+wallclock %F %T %z"
hostname

echo "=== A. SOURCE CHECK (read-only) ==="
cd "$SRC" || { echo "SRC MISSING: $SRC"; exit 1; }
echo "src git: $(git rev-parse --short HEAD 2>/dev/null || echo no-git)"
[ -f "$HELPER" ] || { echo "MISSING_HELPER: $HELPER"; exit 1; }
[ -f "$PARQ" ] || { echo "MISSING_PARQUET: $PARQ"; exit 1; }
echo "parquet bytes=$(stat -c%s "$PARQ") sha256=$(sha256sum "$PARQ" | cut -c1-16)"
declare -A RUN
for a in C4 C4_s200 C4_s300; do
  n=$(ls -d results/33_transformer_recipe_repair/$a/transformer_recipe_repair_${a}_2026_* 2>/dev/null | wc -l)
  [ "$n" -eq 1 ] || { echo "EXPECTED_ONE_RUNDIR for $a, got $n"; ls -d results/33_transformer_recipe_repair/$a/* 2>/dev/null; exit 1; }
  d=$(ls -d results/33_transformer_recipe_repair/$a/transformer_recipe_repair_${a}_2026_*)
  RUN[$a]="$d"
  for f in model_epoch030.pt config.yml train_data/train_data_scaler.yml validation/model_epoch030/validation_results.p validation/model_epoch030/validation_metrics.csv; do
    [ -f "$d/$f" ] || { echo "MISSING $d/$f"; ls "$d" "$d/train_data" "$d/validation/model_epoch030" 2>/dev/null; exit 1; }
  done
  echo "  $a -> $d"
  ( cd "$d" && sha256sum model_epoch030.pt config.yml train_data/train_data_scaler.yml validation/model_epoch030/validation_results.p | cut -c1-16,65- | sed 's/^/    /' )
  echo "    validation_results.p bytes=$(stat -c%s "$d/validation/model_epoch030/validation_results.p")"
  echo "    seed line: $(grep -E '^seed:' "$d/config.yml")"
done

echo "=== B. NEW LANDING (copy, never move) ==="
mkdir -p "$DST/base" "$DST/logs" "$DST/exports"
for a in C4 C4_s200 C4_s300; do
  d="${RUN[$a]}"
  mkdir -p "$DST/base/$a/train_data" "$DST/base/$a/validation/model_epoch030"
  cp -n "$d/model_epoch030.pt" "$d/config.yml" "$DST/base/$a/"
  cp -n "$d/train_data/train_data_scaler.yml" "$DST/base/$a/train_data/"
  cp -n "$d/validation/model_epoch030/validation_results.p" "$d/validation/model_epoch030/validation_metrics.csv" "$DST/base/$a/validation/model_epoch030/"
  echo "$SRC/$d" > "$DST/base/$a/SOURCE_RUN_DIR.txt"
done
( cd "$DST/base" && find . -type f | LC_ALL=C sort | xargs sha256sum ) > "$DST/base/MANIFEST.sha256"
echo "landing files: $(wc -l < "$DST/base/MANIFEST.sha256")"
du -sh "$DST/base" | cut -f1

echo "=== C. EXTRACT (login node, single thread) ==="
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
python -c "import sys, numpy, pandas, xarray; print('python', sys.version.split()[0], 'numpy', numpy.__version__, 'pandas', pandas.__version__, 'xarray', xarray.__version__)"
python -u "$HELPER" "$DST" "$PARQ" 2>&1 | tee "$DST/exports/extract_0b1.log"
gzip -n -f "$DST/exports/track0_forcing_4basins.csv"
ls -la "$DST/exports"

echo "=== D. PACK + BASE64 ==="
TMP=$(mktemp -d)
P="$TMP/pida_0b1"
mkdir -p "$P/C4_s100/train_data"
cp "$DST/base/C4/config.yml" "$DST/base/C4/model_epoch030.pt" "$DST/base/C4/SOURCE_RUN_DIR.txt" "$P/C4_s100/"
cp "$DST/base/C4/train_data/train_data_scaler.yml" "$P/C4_s100/train_data/"
cp "$DST/base/MANIFEST.sha256" "$P/"
cp "$DST/exports/c4_s100_tune_year_sim_obs.npz" "$DST/exports/track0_forcing_4basins.csv.gz" "$DST/exports/extract_0b1.log" "$P/"
( cd "$P" && find . -type f | LC_ALL=C sort | xargs sha256sum ) > "$P/PACK_MANIFEST.sha256"
( cd "$TMP" && tar --mtime='2026-01-01 00:00:00' --owner=0 --group=0 --numeric-owner -czf pida_0b1.tar.gz pida_0b1 )
echo "tar bytes=$(stat -c%s "$TMP/pida_0b1.tar.gz") sha256=$(sha256sum "$TMP/pida_0b1.tar.gz" | cut -c1-16)"
echo "-----BEGIN TARGZ B64-----"
base64 -w 0 "$TMP/pida_0b1.tar.gz"; echo
echo "-----END TARGZ B64-----"
rm -rf "$TMP"

echo "=== E. QUEUE (informational) ==="
echo "my jobs in queue: $(squeue -u sunyiq -h 2>/dev/null | wc -l)"
date "+wallclock %F %T %z"
echo "=== DONE ==="
