#!/bin/bash
# TUKF09-455: read-only comparison of the capsule manifest identity against the v2r7 config.
set -o pipefail
CAPSULE=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_training_source_capsule_v2_20260901
CFG=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r7_20260904/bundle/kalmannet/configs/tukf09_455_basin_zero_validation_target_variance_hpc_execution_a800_exclusive_v2r7.json
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PYEOF2'
import json
capsule = json.load(open("/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_training_source_capsule_v2_20260901/evidence/source_capsule_manifest.json"))
config = json.load(open("/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r7_20260904/bundle/kalmannet/configs/tukf09_455_basin_zero_validation_target_variance_hpc_execution_a800_exclusive_v2r7.json"))
a = capsule.get("scientific_identity")
b = config.get("scientific_identity")
print("EQUAL:", a == b)
keys = sorted(set(a) | set(b))
for k in keys:
    if a.get(k) != b.get(k):
        print("DIFF", k)
        print("   capsule:", json.dumps(a.get(k), ensure_ascii=False))
        print("   config :", json.dumps(b.get(k), ensure_ascii=False))
print("capsule data_identity_sha256:", capsule.get("data_identity_sha256"))
print("capsule file_count:", capsule.get("file_count"), "total_bytes:", capsule.get("total_bytes"))
print("capsule schema:", capsule.get("schema_version"), "purpose:", capsule.get("purpose"))
PYEOF2
echo "=== capsule is read-only ==="
ls -ld "$CAPSULE" "$CAPSULE/evidence" 2>&1
echo "=== v2r7 failure marker ==="
cat /data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r7_20260904/status/PREPARATION_FAILED.json 2>&1
echo "TUKF09_455_CAPSULE_IDENTITY_DIFF_READ_ONLY"
