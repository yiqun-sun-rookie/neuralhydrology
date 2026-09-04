#!/usr/bin/env bash
set -o pipefail

OLD_R2="/data1/home/sunyiq/zhenjiang_six_source_four_target_differentiable_ukf_20260901_r2"
OLD_RECOVERY="/data1/home/sunyiq/zhenjiang_six_source_four_target_differentiable_ukf_20260902_recovery_attempt_002"
NEW_ROOT="/data1/home/sunyiq/zhenjiang_five_source_five_target_single_analysis_ukf_oracle_datong_20260904_r1"

echo "=== A. PROVENANCE ==="
date --iso-8601=seconds
hostname
whoami

echo "=== B. NEW ROOT MUST STILL BE ABSENT ==="
if [ -e "$NEW_ROOT" ]; then
  stat -c 'NEW_ROOT|PRESENT|type=%F|inode=%i|owner=%U:%G|mode=%a|mtime=%y|path=%n' "$NEW_ROOT"
else
  echo "NEW_ROOT|ABSENT|path=$NEW_ROOT"
fi

echo "=== C. EXACT INPUT LOCATIONS IN PROTECTED ROOTS ==="
for root in "$OLD_R2" "$OLD_RECOVERY"; do
  echo "--- ROOT=$root ---"
  for name in \
    dataset_config.json \
    datong_realtime_features.csv \
    nanjing_realtime_features.csv \
    zhenjiang_realtime_features.csv \
    jiangyin_realtime_features.csv \
    xuliujing_realtime_features.csv \
    wusongkou_realtime_features.csv \
    nanjing_retrospective_targets.csv \
    zhenjiang_retrospective_targets.csv \
    jiangyin_retrospective_targets.csv \
    xuliujing_retrospective_targets.csv \
    wusongkou_retrospective_targets.csv \
    tide_model.json; do
    find "$root" -type f -name "$name" -printf 'FOUND|%s|%TY-%Tm-%TdT%TH:%TM:%TS|%p\n' 2>/dev/null || true
  done
done

echo "=== D. ISOLATED INPUT MANIFEST REFERENCES ==="
for manifest in \
  "$OLD_R2/evidence/development_2023/isolated_input_manifest.json" \
  "$OLD_R2/run/docs/records/ZHENJIANG_SIX_SOURCE_FOUR_TARGET_D32_GRU_DIFFERENTIABLE_UKF_V1_REGISTRY.json" \
  "$OLD_RECOVERY/evidence/development_2023/evaluation/attempt_002/completion_manifest.json"; do
  if [ -f "$manifest" ]; then
    echo "--- FILE=$manifest ---"
    stat -c 'META|%s|%y|%n' "$manifest"
    grep -E 'input|dataset_config|realtime_features|retrospective_targets|tide_model|isolated' "$manifest" | head -80 || true
  else
    echo "ABSENT|$manifest"
  fi
done

echo "=== E. SHARED ENVIRONMENT LOCATION ONLY ==="
if [ -f /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh ]; then
  . /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
elif [ -f /data1/home/sunyiq/anaconda3/etc/profile.d/conda.sh ]; then
  . /data1/home/sunyiq/anaconda3/etc/profile.d/conda.sh
fi
conda activate nh_final 2>&1 || true
command -v python || true
python --version 2>&1 || true

echo "=== F. OWN QUEUE, NO CHANGES ==="
squeue -u sunyiq -h -o '%i|%j|%T|%P|%M|%R|%Z' || true

echo "=== G. READ-ONLY QUERY COMPLETE ==="
echo "new_root_created=no"
echo "formal_dataset_content_read=no"
echo "job_submitted_or_changed=no"
