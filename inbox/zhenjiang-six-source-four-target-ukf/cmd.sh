#!/bin/bash
# seq=70 read-only forensic sweep for the six-source four-target differentiable UKF family.
# Submits nothing, writes nothing into any experiment root, reads no 2023/2024 dataset.
set -o pipefail

R2=/data1/home/sunyiq/zhenjiang_six_source_four_target_differentiable_ukf_20260901_r2
REC=/data1/home/sunyiq/zhenjiang_six_source_four_target_differentiable_ukf_20260902_recovery_attempt_002
QR=/data1/home/sunyiq/zhenjiang_six_source_four_target_ukf_qr_learning_value_20260903

echo "=== A. HOST AND TIME ==="
hostname
date '+%Y-%m-%d %H:%M:%S %z'

echo "=== B. FROZEN R2 FIVE FORENSIC HASHES ==="
for f in \
  "$R2/run/docs/records/ZHENJIANG_SIX_SOURCE_FOUR_TARGET_D32_GRU_DIFFERENTIABLE_UKF_V1_REGISTRY.json" \
  "$R2/evidence/development_2023/evaluation/attempt_001.partial/development_access_started.json" \
  "$R2/logs/development-2023-217810.out" \
  "$R2/logs/development-2023-217810.err" \
  "$R2/run/scripts/analysis/zhenjiang_six_source_four_target_d32_gru_ukf_development_evaluation_v1.py" ; do
  if [ -f "$f" ]; then
    printf '%s  %s  %s\n' "$(sha256sum "$f" | cut -d' ' -f1)" "$(stat -c %s "$f")" "${f#$R2/}"
  else
    printf 'MISSING  -  %s\n' "${f#$R2/}"
  fi
done

echo "=== C. ISOLATED INPUT MANIFEST ==="
IM="$R2/inputs/pre2024-four-target-v1/four_target_input_manifest.json"
if [ -f "$IM" ]; then
  printf '%s  %s bytes\n' "$(sha256sum "$IM" | cut -d' ' -f1)" "$(stat -c %s "$IM")"
else
  echo "MISSING $IM"
fi

echo "=== D. ORIGINAL ATTEMPT_001 DIRECTORIES MUST STILL NOT EXIST ==="
for d in \
  "$R2/evidence/development_2023/evaluation/attempt_001" \
  "$R2/evidence/development_2023/independent_audit/attempt_001" ; do
  if [ -e "$d" ]; then echo "PRESENT(unexpected)  $d"; else echo "absent(expected)    ${d#$R2/}"; fi
done

echo "=== E. NEWEST MTIME AND COUNTS IN EACH READ-ONLY ROOT ==="
for R in "$R2" "$REC"; do
  echo "--- $R ---"
  find "$R" -type f -printf '%T@ %TY-%Tm-%Td %TH:%TM:%TS %p\n' 2>/dev/null | sort -n | tail -3
  echo "file_count=$(find "$R" -type f 2>/dev/null | wc -l)"
  echo "pycache_dir_count=$(find "$R" -type d -name __pycache__ 2>/dev/null | wc -l)"
done

echo "=== F. ATTEMPT_002 EVALUATION ARTIFACT SET + HASHES ==="
EV="$REC/evidence/development_2023/evaluation/attempt_002"
echo "file_count=$(find "$EV" -type f 2>/dev/null | wc -l)"
find "$EV" -type f -exec sha256sum {} \; 2>/dev/null | sed "s#$EV/##" | sort -k2

echo "=== G. ATTEMPT_002 INDEPENDENT AUDIT ARTIFACT SET + HASHES ==="
AU="$REC/evidence/development_2023/independent_audit/attempt_002"
echo "file_count=$(find "$AU" -type f 2>/dev/null | wc -l)"
find "$AU" -type f -exec sha256sum {} \; 2>/dev/null | sed "s#$AU/##" | sort -k2

echo "=== H. ACCESS/COMPLETION REGISTRATION FILES (metadata only) ==="
for j in $(find "$EV" "$AU" -maxdepth 1 -type f -name '*.json' 2>/dev/null | sort); do
  b=$(basename "$j")
  case "$b" in
    *access*|*completion*|*manifest*|*registr*)
      echo "--- $b ($(stat -c %s "$j") bytes) ---"
      head -c 2200 "$j"
      echo
      ;;
  esac
done

echo "=== I. QR DIAGNOSTIC ROOT PRODUCTS ==="
for S in 17 29 43; do
  D="$QR/runs/qr_learning_value/s$S/attempt_001"
  echo "--- seed $S ---"
  if [ -d "$D" ]; then
    find "$D" -type f -printf '%10s  %f\n' 2>/dev/null | sort -k2
    if [ -f "$D/completion_manifest.json" ]; then
      head -c 1100 "$D/completion_manifest.json"
      echo
    fi
  else
    echo "MISSING $D"
  fi
done

echo "=== J. JOB TERMINAL STATES ==="
sacct -j 217810,218505,219223 -X --format=JobID%14,JobName%24,NodeList%10,State%16,ExitCode%9,Elapsed%12,End%20 2>&1

echo "=== K. CURRENT OWN QUEUE (PrivateData: own jobs only) ==="
squeue -u "$USER" -o "%.12i %.26j %.10P %.9T %.11M %.22R" 2>&1
echo "own_job_lines=$(squeue -u "$USER" -h 2>/dev/null | wc -l)"

echo "=== L. ANY UKF-FAMILY JOB IN FLIGHT? ==="
squeue -u "$USER" -h -o "%i %j %T" 2>/dev/null | grep -iE 'ukf|six_source|qr_learning' || echo "  none"

echo "=== DONE ==="
