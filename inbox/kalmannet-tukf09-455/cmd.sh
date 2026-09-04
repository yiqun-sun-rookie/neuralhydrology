#!/bin/bash
# TUKF09-455: publish a new read-only training source capsule whose frozen scientific
# identity matches the re-signed training admission. The 911 data files are copied byte
# for byte from the superseded capsule and every hash is checked on the way in.
# The superseded capsule is only read. No Slurm job, no training, no formal evaluation.

set -o pipefail

OLD=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_training_source_capsule_v2_20260901
NEW=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_training_source_capsule_v3_20260904
CFG=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r7_20260904/bundle/kalmannet/configs/tukf09_455_basin_zero_validation_target_variance_hpc_execution_a800_exclusive_v2r7.json
PY=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
SELF="$PWD/inbox/kalmannet-tukf09-455/cmd.sh"

echo "TIME=$(date -Is)"
echo "=== GUARDS ==="
test -d "$OLD" || { echo SUPERSEDED_CAPSULE_MISSING; exit 1; }
test -f "$CFG" || { echo CONFIG_MISSING; exit 1; }
case "$NEW" in *capsule_v3_20260904) echo TARGET_OK;; *) echo TARGET_GUARD_FAILED; exit 1;; esac
CMD_SHA=$(sha256sum "$SELF" | cut -d" " -f1)
echo "DEPLOYMENT_COMMAND_SHA256=$CMD_SHA"
echo "SUPERSEDED_CAPSULE_MODE_BEFORE=$(stat -c %a "$OLD")"

echo "=== PUBLISH ==="
"$PY" -B - "$OLD" "$NEW" "$CFG" 106 "$CMD_SHA" <<'PUBLISH_EOF'
import hashlib, json, os, sys
from pathlib import Path, PurePosixPath

OLD = Path(sys.argv[1]); NEW = Path(sys.argv[2]); CFG = Path(sys.argv[3])
SEQ = int(sys.argv[4]); CMD_SHA = sys.argv[5]

manifest = json.loads((OLD / "evidence" / "source_capsule_manifest.json").read_text("utf-8"))
config = json.loads(CFG.read_text("utf-8"))
identity = config["scientific_identity"]

records = manifest["files"]
assert isinstance(records, list) and len(records) == manifest["file_count"] == 911, "unexpected record count"

new_data_root = NEW / "data" / "camels_us"
old_data_root = OLD / "data" / "camels_us"

if NEW.exists():
    print("NEW_CAPSULE_ALREADY_EXISTS"); sys.exit(1)
NEW.mkdir(mode=0o755)
(NEW / "evidence").mkdir(mode=0o755)

total = 0
for record in records:
    rel = PurePosixPath(record["relative_path"])
    src = old_data_root.joinpath(*rel.parts)
    dst = new_data_root.joinpath(*rel.parts)
    if src.is_symlink() or not src.is_file():
        print("SOURCE_NOT_A_REGULAR_FILE", rel); sys.exit(2)
    digest = hashlib.sha256()
    dst.parent.mkdir(parents=True, exist_ok=True)
    with src.open("rb") as reader, dst.open("xb") as writer:
        while True:
            chunk = reader.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
            writer.write(chunk)
        writer.flush(); os.fsync(writer.fileno())
    if digest.hexdigest() != record["sha256"] or dst.stat().st_size != int(record["size_bytes"]):
        print("COPY_MISMATCH", rel); sys.exit(3)
    if dst.stat().st_nlink != 1:
        print("COPIED_FILE_IS_HARD_LINKED", rel); sys.exit(4)
    total += int(record["size_bytes"])
print("COPIED_FILES", len(records), "TOTAL_BYTES", total)
assert total == manifest["total_bytes"], "total byte mismatch"

identity_rows = sorted(
    ({"relative_path": r["relative_path"], "size_bytes": int(r["size_bytes"]), "sha256": r["sha256"]}
     for r in records),
    key=lambda row: row["relative_path"],
)
identity_sha = hashlib.sha256(
    json.dumps(identity_rows, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
).hexdigest()
assert identity_sha == manifest["data_identity_sha256"], "identity digest drifted"
print("DATA_IDENTITY_SHA256", identity_sha)

new_manifest = dict(manifest)
new_manifest["scientific_identity"] = identity
new_manifest["capsule_root"] = os.fspath(NEW)
new_manifest["capsule_data_root"] = os.fspath(new_data_root)
new_manifest["capsule_deployment_mailbox_sequence"] = SEQ
new_manifest["capsule_deployment_command_sha256"] = CMD_SHA
new_manifest["supersedes_capsule_root"] = os.fspath(OLD)
new_manifest["supersedes_reason"] = (
    "the training admission was re-signed when the graphics-process probe parser was "
    "corrected, so the frozen scientific identity moved"
)
new_manifest["data_bytes_identical_to_superseded_capsule"] = True

newline = chr(10).encode("ascii")
manifest_bytes = json.dumps(new_manifest, ensure_ascii=False, sort_keys=True, indent=1).encode("utf-8") + newline
(NEW / "evidence" / "source_capsule_manifest.json").write_bytes(manifest_bytes)
manifest_sha = hashlib.sha256(manifest_bytes).hexdigest()
record_bytes = (manifest_sha + "  source_capsule_manifest.json" + chr(10)).encode("ascii")
(NEW / "evidence" / "source_capsule_manifest.sha256").write_bytes(record_bytes)

ready = {
    "schema_version": "tukf09_455_training_source_capsule_ready_v2",
    "status": "READY",
    "capsule_root": os.fspath(NEW),
    "capsule_data_root": os.fspath(new_data_root),
    "manifest_relative_path": "evidence/source_capsule_manifest.json",
    "manifest_size": len(manifest_bytes),
    "manifest_sha256": manifest_sha,
    "data_file_count": len(records),
    "data_total_bytes": total,
    "data_identity_sha256": identity_sha,
    "deployment_mailbox_sequence": SEQ,
    "deployment_command_sha256": CMD_SHA,
    "validity_gate": "exact_ready_json_and_manifest_and_911_files_and_all_directories_mode_0555",
    "required_capsule_root_mode": "0555",
    "required_all_directory_mode": "0555",
    "required_all_file_mode": "0444",
    "formal_evaluation_array_reads": 0,
    "formal_evaluation_predictions": 0,
    "formal_evaluation_metrics": 0,
    "formal_evaluation_outputs": 0,
}
ready_bytes = json.dumps(ready, ensure_ascii=False, sort_keys=True, indent=1).encode("utf-8") + newline
(NEW / "evidence" / "READY.json").write_bytes(ready_bytes)

files = dirs = 0
for directory, _names, filenames in os.walk(NEW, topdown=False):
    for name in filenames:
        os.chmod(Path(directory) / name, 0o444); files += 1
    os.chmod(directory, 0o555); dirs += 1
print("MODE_SET files", files, "dirs", dirs)

print("CAPSULE_ROOT", os.fspath(NEW))
print("CAPSULE_DATA_ROOT", os.fspath(new_data_root))
print("MANIFEST_SIZE", len(manifest_bytes))
print("MANIFEST_SHA256", manifest_sha)
print("MANIFEST_RECORD_SIZE", len(record_bytes))
print("MANIFEST_RECORD_SHA256", hashlib.sha256(record_bytes).hexdigest())
print("READY_SIZE", len(ready_bytes))
print("READY_SHA256", hashlib.sha256(ready_bytes).hexdigest())
print("DATA_FILE_COUNT", len(records))
print("TOTAL_FILE_COUNT", len(records) + 3)
print("DIRECTORY_COUNT", dirs)
print("DATA_TOTAL_BYTES", total)
print("PUBLICATION_OK")
PUBLISH_EOF
RC=$?
echo "PUBLISH_RETURN_CODE=$RC"
if [ "$RC" -ne 0 ]; then echo PUBLICATION_FAILED; exit "$RC"; fi

echo "=== SURFACE ==="
ls -ld "$NEW" "$NEW/data" "$NEW/data/camels_us" "$NEW/evidence" 2>&1
echo "FILES=$(find "$NEW" -type f | wc -l)"
echo "DIRS=$(find "$NEW" -type d | wc -l)"
echo "SYMLINKS=$(find "$NEW" -type l | wc -l)"
echo "HARDLINKED=$(find "$NEW" -type f -links +1 | wc -l)"
cat "$NEW/evidence/source_capsule_manifest.sha256"
echo "=== SUPERSEDED CAPSULE UNTOUCHED ==="
echo "SUPERSEDED_CAPSULE_MODE_AFTER=$(stat -c %a "$OLD")"
sha256sum "$OLD/evidence/source_capsule_manifest.json" "$OLD/evidence/READY.json" 2>&1
echo "SUPERSEDED_FILES=$(find "$OLD" -type f | wc -l)"

echo TUKF09_455_TRAINING_SOURCE_CAPSULE_V3_PUBLISHED_NO_JOB_SUBMITTED
