#!/bin/bash
set -eo pipefail
sequence=2

echo "=== identity ==="
date -Is
hostname

echo "=== conda environments ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || source "$HOME/miniconda3/etc/profile.d/conda.sh"
conda env list

echo "=== exact cached packages ==="
for pattern in \
  '/data1/home/sunyiq/miniconda3/pkgs/python-3.11.5-*' \
  '/data1/home/sunyiq/miniconda3/pkgs/numpy-1.26.4-*' \
  '/data1/home/sunyiq/miniconda3/pkgs/pytorch-2.2.2-*' \
  '/data1/home/sunyiq/miniconda3/pkgs/torch-2.2.2-*'; do
  matches=$(compgen -G "$pattern" || true)
  if test -n "$matches"; then
    printf '%s\n' "$matches"
  else
    echo "NO_MATCH $pattern"
  fi
done

echo "=== available isolated runtime tools ==="
for tool in conda micromamba apptainer singularity; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf '%s=' "$tool"
    command -v "$tool"
  else
    echo "ABSENT $tool"
  fi
done

echo "=== exact Regge and ID23 top-level candidates ==="
found=0
for pattern in '/data1/home/sunyiq/*regge*' '/data1/home/sunyiq/*Regge*' '/data1/home/sunyiq/id23*'; do
  matches=$(compgen -G "$pattern" || true)
  if test -n "$matches"; then
    found=1
    while IFS= read -r path; do
      stat -c '%A %U %G %s %y %n' "$path"
    done <<< "$matches"
  fi
done
if test "$found" -eq 0; then
  echo "NO_TOP_LEVEL_CANDIDATES"
fi

echo "=== exact archive directory names under candidate roots ==="
for base in $(compgen -G '/data1/home/sunyiq/id23*' || true) $(compgen -G '/data1/home/sunyiq/*regge*' || true); do
  test -d "$base" || continue
  find "$base" -maxdepth 5 -type d \( \
    -name '20260920-regge-short-record-recovery-v03-001' -o \
    -name '20260927-regge-short-record-selection-development-001' -o \
    -name '20260929-002' \) -print
done

echo "=== partition policies ==="
scontrol show partition hcpu48 | grep -E 'PartitionName=|OverSubscribe=|TotalCPUs=|TotalNodes='
scontrol show partition hgpu2p | grep -E 'PartitionName=|OverSubscribe=|TotalCPUs=|TotalNodes='
