#!/bin/bash
# TUKF09-455: publish training source capsule v7.
#
# The data is byte-identical to capsule v6: the same 911 files and 464792200 bytes, each
# copied and re-hashed against v5's own manifest, and the data identity digest is
# recomputed and required to match. Only the frozen scientific identity moves.
#
# v6 and every older capsule are read only here. Nothing is deleted, no old root is
# touched, no job is submitted.
set -eo pipefail
OLD=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_training_source_capsule_v6_20260908
NEW=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_training_source_capsule_v7_20260909
SELF_SHA=$(sha256sum "$0" | cut -d" " -f1)
echo "TIME=$(date -Is)  SEQ=152  CMD_SHA=${SELF_SHA}"

echo "=== PRECONDITIONS ==="
test -d "$OLD" || { echo "SUPERSEDED_CAPSULE_MISSING"; exit 10; }
test -f "$OLD/evidence/source_capsule_manifest.json" || { echo "SUPERSEDED_MANIFEST_MISSING"; exit 11; }
if [ -e "$NEW" ]; then echo "NEW_CAPSULE_ALREADY_EXISTS"; exit 12; fi
echo "OLD_MANIFEST_SHA256=$(sha256sum "$OLD/evidence/source_capsule_manifest.json" | cut -d" " -f1)"
echo "OLD_ROOT_MODE=$(stat -c %a "$OLD")"
df -h /data1/home/sunyiq | tail -1

WORK=$(mktemp -d /data1/home/sunyiq/.tukf09_capsule_v7.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/identity.json" <<'IDENTITY_EOF'
{
 "all_scope_authorization": {
  "path": "artifacts/tukf09_455_basin_zero_validation_target_variance_revision_v1/authorizations/all_scope_authorization.json",
  "sha256": "7f94c1b75d55f72b399b50c528873c9dc8da2c39a6cfd78f8a1ce80a4c71bc80"
 },
 "excluded_basins": [
  "08202700"
 ],
 "filter_migration_final_manifest": {
  "path": "artifacts/tukf09_455_basin_zero_validation_target_variance_revision_v1/filter_migration_v1/independent/manifest.final.sha256.json",
  "sha256": "13bd4e78d56c62ce48942c003462844ab73a6f472533aeb7bbf4f4ad12f0329a"
 },
 "formal_training_execution": {
  "path": "configs/tukf09_455_basin_zero_validation_target_variance_formal_training_execution_v1.json",
  "sha256": "01a32fa6fc82fe134d54237ca0368614afbca8f4361b95326860685c0a29308c"
 },
 "independent_preflight_final_manifest": {
  "path": "artifacts/tukf09_455_basin_zero_validation_target_variance_revision_v1/preflight/independent/manifest.final.sha256.json",
  "sha256": "f7e0a3f0708d0498cbaeaa77a044687f20d017ffa316170cd4770fc920b144aa"
 },
 "local_filter_installation_final_manifest": {
  "path": "results/tukf09_455_basin_zero_validation_target_variance_revision_v1/control/filter_rebinding/independent/manifest.final.sha256.json",
  "sha256": "ec222536b144e256e152cdaa857440d4482abac74c4eaf7ca6ab9dd8340bb79c"
 },
 "ordered_basin_compact_json_sha256": "75ef2cee206fb15ee3f31ae0bbfcf594661c5ccdda0b28de9ff65634332c8902",
 "ordered_basin_count": 455,
 "ordered_basin_newline_sha256": "38987bce45fa38ff68f5b067db17e8cb3212d98fecdd106f57d268a130ee8fbd",
 "original_training_admission": {
  "file_sha256": "43aafca6bc7b1d2dd18dcb872c76e831455d847710ca55e2a351f5537d4e776d",
  "path": "artifacts/tukf09_455_basin_zero_validation_target_variance_revision_v1/training_admission/training_admission.json",
  "record_sha256": "a44675237a8fd41761ed9ab5a7627f3eeecaa186eed29c91c110d0d32d41313a"
 },
 "scientific_contract": {
  "path": "configs/tukf09_455_basin_zero_validation_target_variance_revision_v1.json",
  "sha256": "7710594dcc5cce7f087cb70492a6f827c3925a98ea7fa051d26c5ef1660304e1"
 }
}
IDENTITY_EOF
echo "IDENTITY_SHA256_EXPECTED=c0a4874777bae8f84d3cacb730a399e59322a5a7deca998afcda16dd37785a57"
echo "IDENTITY_SHA256_ACTUAL=$(sha256sum "$WORK/identity.json" | cut -d" " -f1)"

cat > "$WORK/publish_capsule_v7.py" <<'PUBLISHER_EOF'
import hashlib, json, os, sys
from pathlib import Path, PurePosixPath

OLD = Path(sys.argv[1]); NEW = Path(sys.argv[2]); IDENTITY_JSON = Path(sys.argv[3])
SEQ = int(sys.argv[4]); CMD_SHA = sys.argv[5]

manifest = json.loads((OLD / "evidence" / "source_capsule_manifest.json").read_text("utf-8"))
identity = json.loads(IDENTITY_JSON.read_text("utf-8"))

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
    "the filter migration was re-run so the 455 unit identities carry the "
    "authorization now in force, and the training admission was signed again after "
    "the population check that ended job 220663 was repaired, so the frozen "
    "scientific identity moved"
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
PUBLISHER_EOF
echo "PUBLISHER_SHA256_EXPECTED=b5d57ff1c2d829f5f244352b73c19ce82af7ced211c5e7027ba047ca0ca3fefb"
echo "PUBLISHER_SHA256_ACTUAL=$(sha256sum "$WORK/publish_capsule_v7.py" | cut -d" " -f1)"

echo "=== PUBLISH ==="
source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh" || source "${HOME}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final || { echo CONDA_FAILED; exit 13; }
python -X utf8 "$WORK/publish_capsule_v7.py" "$OLD" "$NEW" "$WORK/identity.json" 152 "$SELF_SHA"

echo "=== PUBLISHED CAPSULE ==="
ls -la "$NEW" "$NEW/evidence" 2>&1
echo "ROOT_MODE=$(stat -c %a "$NEW")"
cat "$NEW/evidence/READY.json"
echo "MANIFEST_RECORD=$(cat "$NEW/evidence/source_capsule_manifest.sha256")"

echo "=== EVERY OLDER CAPSULE UNCHANGED ==="
for c in v2 v3 v4 v5 v6; do d=$(ls -d /data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_training_source_capsule_${c}_2026* 2>/dev/null | head -1); echo "CAPSULE_${c}=${d:-<absent>} mode=$(stat -c %a "$d" 2>/dev/null) manifest=$(sha256sum "$d/evidence/source_capsule_manifest.json" 2>/dev/null | cut -d" " -f1)"; done

echo TUKF09_455_CAPSULE_V7_PUBLISHED_NOTHING_ELSE_TOUCHED
