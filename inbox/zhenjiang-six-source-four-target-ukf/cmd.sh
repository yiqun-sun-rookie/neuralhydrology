#!/bin/bash
# seq=71 read-only collision and isolation probe for the planned five-source,
# five-target, single-analysis UKF experiment root.
# Creates no directory, submits/cancels no job, reads no dataset, and does not
# traverse or modify either protected historical experiment root.
set -o pipefail
export LC_ALL=C

PARENT=/data1/home/sunyiq
PROTECTED_R2=/data1/home/sunyiq/zhenjiang_six_source_four_target_differentiable_ukf_20260901_r2
PROTECTED_REC=/data1/home/sunyiq/zhenjiang_six_source_four_target_differentiable_ukf_20260902_recovery_attempt_002
PREFIX=/data1/home/sunyiq/zhenjiang_five_source_five_target_single_analysis_ukf_oracle_datong_20260904_r
CANDIDATE="${PREFIX}1"
FAMILY=ZHENJIANG_FIVE_SOURCE_FIVE_TARGET_D32_GRU_SINGLE_ANALYSIS_UKF_ORACLE_DATONG_V2

show_exact_path() {
  LABEL="$1"
  EXACT_PATH="$2"
  if [ -e "$EXACT_PATH" ] || [ -L "$EXACT_PATH" ]; then
    printf '%s|EXISTS|' "$LABEL"
    stat -c 'type=%F|inode=%i|owner=%U:%G|mode=%a|mtime=%y|path=%n' -- "$EXACT_PATH" 2>&1
  else
    printf '%s|ABSENT|path=%s\n' "$LABEL" "$EXACT_PATH"
  fi
}

echo "=== A. QUERY PROVENANCE AND PLANNED IDENTITY ==="
printf 'timestamp='; date -Is
printf 'hostname='; hostname
printf 'user=%s\n' "${USER:-sunyiq}"
printf 'family=%s\n' "$FAMILY"
printf 'candidate=%s\n' "$CANDIDATE"

echo "=== B. PARENT DIRECTORY METADATA (NO WRITE TEST) ==="
show_exact_path PARENT "$PARENT"
if [ -w "$PARENT" ]; then echo "parent_permission=writable"; else echo "parent_permission=not_writable"; fi
df -hP "$PARENT" 2>&1 | tail -n 1

echo "=== C. PROTECTED HISTORICAL ROOTS (TOP-LEVEL METADATA ONLY) ==="
show_exact_path PROTECTED_R2 "$PROTECTED_R2"
show_exact_path PROTECTED_RECOVERY "$PROTECTED_REC"

echo "=== D. EXACT CANDIDATE CHECK ==="
show_exact_path CANDIDATE_R1 "$CANDIDATE"

echo "=== E. SAME-PREFIX NEIGHBORS (TOP LEVEL ONLY) ==="
PREFIX_MATCH_COUNT=0
for PATH_MATCH in "${PREFIX}"*; do
  [ -e "$PATH_MATCH" ] || [ -L "$PATH_MATCH" ] || continue
  PREFIX_MATCH_COUNT=$((PREFIX_MATCH_COUNT + 1))
  printf 'PREFIX_MATCH|'
  stat -c 'type=%F|inode=%i|owner=%U:%G|mode=%a|mtime=%y|path=%n' -- "$PATH_MATCH" 2>&1
done
printf 'PREFIX_MATCH_COUNT=%s\n' "$PREFIX_MATCH_COUNT"

echo "=== F. CURRENT OWN QUEUE ==="
squeue -u "${USER:-sunyiq}" -o '%.18i|%.40j|%.10T|%.12P|%.12M|%.40R|%Z' 2>&1
printf 'SQUEUE_RC=%s\n' "$?"

echo "=== G. RELEVANT-NAME JOBS ==="
RELEVANT=$(squeue -u "${USER:-sunyiq}" -h -o '%i|%j|%T|%P|%R|%Z' 2>/dev/null | \
  grep -iE 'zhenjiang|five[_-]?source|ukf|datong|oracle' || true)
if [ -n "$RELEVANT" ]; then printf '%s\n' "$RELEVANT"; else echo "relevant_name_jobs=none"; fi

echo "=== H. EXACT CANDIDATE REFERENCES IN OWN ACTIVE/PENDING JOB DETAILS ==="
CANDIDATE_REFERENCE_COUNT=0
for JOB_ID in $(squeue -u "${USER:-sunyiq}" -h -o '%i' 2>/dev/null | sort -u); do
  JOB_DETAIL=$(scontrol show job "$JOB_ID" -o 2>/dev/null || true)
  if printf '%s\n' "$JOB_DETAIL" | grep -F -- "$CANDIDATE" >/dev/null 2>&1; then
    printf 'CANDIDATE_REFERENCE_JOB=%s\n' "$JOB_ID"
    printf '%s\n' "$JOB_DETAIL"
    CANDIDATE_REFERENCE_COUNT=$((CANDIDATE_REFERENCE_COUNT + 1))
  fi
done
printf 'CANDIDATE_REFERENCE_JOB_COUNT=%s\n' "$CANDIDATE_REFERENCE_COUNT"

echo "=== I. READ-ONLY PROBE COMPLETED ==="
echo "directory_created=no"
echo "job_submitted_or_changed=no"
echo "dataset_read=no"
