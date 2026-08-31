#!/bin/bash
# Read-only forensics for the v2r2 deployment compatibility stop.
set -eo pipefail

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r2_20260901
V2R1_ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r1_20260901
V2_ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2_20260831

test -d "${ROOT}"
test ! -L "${ROOT}"
echo "=== V2R2 PARTIAL ROOT INVENTORY ==="
du -sb "${ROOT}"
find "${ROOT}" -mindepth 1 -maxdepth 4 -printf '%y|%p|%s|%n|%m\n' | LC_ALL=C sort

test -d "${ROOT}/incoming"
test ! -L "${ROOT}/incoming"
test -d "${ROOT}/logs"
test ! -L "${ROOT}/logs"
test -d "${ROOT}/status"
test ! -L "${ROOT}/status"
test "$(find "${ROOT}" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 3
test "$(find "${ROOT}" -mindepth 1 -type f | wc -l)" -eq 0
test "$(find "${ROOT}" -mindepth 1 -type l | wc -l)" -eq 0
for absent in \
  "${ROOT}/bundle" \
  "${ROOT}/offline_inputs_v2r2" \
  "${ROOT}/runtime_v2r2" \
  "${ROOT}/status/allocation_probe.json" \
  "${ROOT}/status/preparation_probe.json" \
  "${ROOT}/status/hpc_technical_admission.json" \
  "${ROOT}/results"; do
  test ! -e "${absent}"
  test ! -L "${absent}"
  echo "ABSENT=${absent}"
done

echo "=== COPY IMPLEMENTATION ==="
cp --version
cp --help | grep -- '--reflink'

echo "=== JOB ABSENCE ==="
if squeue -h -o '%i|%j|%T' | grep -E 'tukf09-455-v2r2-(map|prepare|neural)'; then
  echo "UNEXPECTED_V2R2_JOB" >&2
  exit 72
fi
echo "NO_V2R2_SLURM_JOB"

echo "=== PREDECESSOR FREEZE ==="
test "$(sha256sum "${V2R1_ROOT}/status/initial_bundle_verification.json" | awk '{print $1}')" = "e1439af9226a3e94d7b8951e4f471e8c678990e3fbeb366c2e919cf9a3eae6b7"
test "$(sha256sum "${V2R1_ROOT}/runtime_v2r1.pending.217163/evidence/pip-stdout.log" | awk '{print $1}')" = "f2b4b652eb10ebbf157a9d08a1871328059ced1aa941a8a7d41e14de9ce5be84"
test "$(sha256sum "${V2R1_ROOT}/runtime_v2r1.pending.217163/evidence/pip-stderr.log" | awk '{print $1}')" = "f9e8fe66ce1f3834235bba544f558c7cf0e45ac077dda75e119a97f0311dc71c"
test "$(sha256sum "${V2_ROOT}/status/initial_bundle_verification.json" | awk '{print $1}')" = "b1b4c0f39187cb6c46cf4234f7da4131b33f2ffa35c523abf02eab6fdf38d0b9"
test "$(sha256sum "${V2_ROOT}/runtime_v2.pending.217149/evidence/pip-stdout.log" | awk '{print $1}')" = "37cf0cb26683b2a97c6484d52c2c90f0a5bb10356cfd097a0d599e7999a9b8ab"
test "$(sha256sum "${V2_ROOT}/runtime_v2.pending.217149/evidence/pip-stderr.log" | awk '{print $1}')" = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

echo "TUKF09_455_A800_EXCLUSIVE_V2R2_DEPLOYMENT_COMPATIBILITY_STOP_FROZEN"
