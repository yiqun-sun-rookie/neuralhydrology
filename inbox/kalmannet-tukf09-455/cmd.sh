#!/bin/bash
# TUKF09-455: independent post-publication audit of training source capsule v3.
# Read-only. Re-hashes all 911 files from disk, checks them against the frozen raw
# source manifest, checks the frozen population order, modes and surface.
# Publishes nothing, submits nothing, modifies nothing.

set -o pipefail

CAP=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_training_source_capsule_v3_20260904
OLD=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_training_source_capsule_v2_20260901
PROJECT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r7_20260904/bundle/kalmannet
PY=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
SELF="$PWD/inbox/kalmannet-tukf09-455/cmd.sh"

echo "TIME=$(date -Is)"
echo "AUDIT_COMMAND_SHA256=$(sha256sum "$SELF" | cut -d" " -f1)"
test -d "$CAP" || { echo CAPSULE_MISSING; exit 1; }
test -d "$PROJECT" || { echo PROJECT_MISSING; exit 1; }

echo "=== INDEPENDENT AUDIT ==="
"$PY" -B - "$CAP" "$PROJECT" <<'AUDIT_EOF'
import hashlib, json, os, stat, sys
from pathlib import Path, PurePosixPath

CAP = Path(sys.argv[1]); PROJECT = Path(sys.argv[2])

manifest_path = CAP / "evidence" / "source_capsule_manifest.json"
ready_path = CAP / "evidence" / "READY.json"
record_path = CAP / "evidence" / "source_capsule_manifest.sha256"
manifest_bytes = manifest_path.read_bytes()
manifest = json.loads(manifest_bytes.decode("utf-8"))
ready = json.loads(ready_path.read_bytes().decode("utf-8"))
data_root = CAP / "data" / "camels_us"

failures = []

def check(name, condition):
    if not condition:
        failures.append(name)

check("manifest_sha_record_matches",
      record_path.read_bytes()
      == (hashlib.sha256(manifest_bytes).hexdigest() + "  source_capsule_manifest.json" + chr(10)).encode("ascii"))
check("ready_binds_manifest", ready["manifest_sha256"] == hashlib.sha256(manifest_bytes).hexdigest())
check("ready_manifest_size", ready["manifest_size"] == len(manifest_bytes))
check("capsule_root", manifest["capsule_root"] == os.fspath(CAP) == ready["capsule_root"])
check("capsule_data_root", manifest["capsule_data_root"] == os.fspath(data_root) == ready["capsule_data_root"])
check("ready_status", ready["status"] == "READY")

# The frozen raw source manifest is the authority for what the 911 files must be.
raw_relative = manifest["raw_source_manifest_relative_path"]
raw_path = PROJECT.joinpath(*PurePosixPath(raw_relative).parts)
raw_bytes = raw_path.read_bytes()
check("raw_manifest_size", manifest["raw_source_manifest_size"] == len(raw_bytes))
check("raw_manifest_sha256", manifest["raw_source_manifest_sha256"] == hashlib.sha256(raw_bytes).hexdigest())
raw = json.loads(raw_bytes.decode("utf-8"))
raw_files = raw["files"]

records = {r["relative_path"]: r for r in manifest["files"]}
check("record_count", len(records) == len(manifest["files"]) == 911)

# 910 of the 911 files are forcing and discharge files covered by the frozen raw source
# manifest. The 911th is the catchment topography file, which the execution config pins
# separately, so it is checked against that instead.
staging = json.loads(
    (PROJECT / "configs/tukf09_455_basin_zero_validation_target_variance_hpc_execution_a800_exclusive_v2r7.json")
    .read_text("utf-8")
)["data_staging"]
topography = staging["topography_relative_path"]

missing_in_raw = sorted(name for name in records if name not in raw_files)
check("exactly_the_topography_file_is_outside_the_raw_manifest", missing_in_raw == [topography])
check("raw_covered_file_count", len(records) - len(missing_in_raw) == int(staging["staged_raw_file_count"]) == 910)
check("total_staged_file_count", len(records) == int(staging["total_staged_file_count"]) == 911)
if topography in records:
    check("topography_sha256", records[topography]["sha256"] == staging["topography_sha256"])
    check("topography_size", int(records[topography]["size_bytes"]) == int(staging["topography_size_bytes"]))

mismatched = [
    name for name in records
    if name in raw_files
    and (raw_files[name]["sha256"] != records[name]["sha256"]
         or int(raw_files[name]["size_bytes"]) != int(records[name]["size_bytes"]))
]
check("capsule_records_agree_with_the_frozen_raw_manifest", not mismatched)

# Re-hash every file on disk, independently of the manifest that was just written.
total = 0
bad = []
for name, record in sorted(records.items()):
    path = data_root.joinpath(*PurePosixPath(name).parts)
    if path.is_symlink() or not path.is_file() or path.stat().st_nlink != 1:
        bad.append(name); continue
    if stat.S_IMODE(path.stat().st_mode) != 0o444:
        bad.append(name); continue
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    if digest.hexdigest() != record["sha256"] or path.stat().st_size != int(record["size_bytes"]):
        bad.append(name); continue
    total += path.stat().st_size
check("all_911_files_rehash_clean", not bad)
check("total_bytes", total == manifest["total_bytes"] == 464792200)

identity_rows = sorted(
    ({"relative_path": r["relative_path"], "size_bytes": int(r["size_bytes"]), "sha256": r["sha256"]}
     for r in manifest["files"]),
    key=lambda row: row["relative_path"],
)
identity = hashlib.sha256(
    json.dumps(identity_rows, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
).hexdigest()
check("data_identity", identity == manifest["data_identity_sha256"] == ready["data_identity_sha256"])

# The population order is the frozen registry order, never a re-sort.
registry = json.loads(
    (PROJECT / "artifacts/tukf09_455_basin_zero_validation_target_variance_revision_v1/preflight/population_registry.json")
    .read_text("utf-8")
)
basins = registry["eligible"]
check("registry_is_a_list_of_455", isinstance(basins, list) and len(basins) == 455)
if isinstance(basins, list):
    newline_digest = hashlib.sha256("".join(b + chr(10) for b in basins).encode("utf-8")).hexdigest()
    check("registry_order_digest", newline_digest == manifest["scientific_identity"]["ordered_basin_newline_sha256"])
    check("registry_self_digest", newline_digest == registry["eligible_ordered_newline_utf8_sha256"])
    check("excluded_basin", registry["validation_metric_undefined"] == ["08202700"])

# Modes and surface.
files = dirs = 0
for directory, _names, filenames in os.walk(CAP):
    dpath = Path(directory)
    if dpath.is_symlink() or stat.S_IMODE(dpath.stat().st_mode) != 0o555:
        failures.append("directory_mode:" + os.fspath(dpath))
    dirs += 1
    for name in filenames:
        fpath = dpath / name
        if fpath.is_symlink() or stat.S_IMODE(fpath.stat().st_mode) != 0o444:
            failures.append("file_mode:" + os.fspath(fpath))
        files += 1
check("surface_counts", files == 914 and dirs == 44)

print("REHASHED_FILES", len(records))
print("REHASH_FAILURES", len(bad))
print("TOTAL_BYTES", total)
print("DATA_IDENTITY_SHA256", identity)
print("FILES", files, "DIRS", dirs)
print("SCIENTIFIC_IDENTITY_SHA256",
      hashlib.sha256(json.dumps(manifest["scientific_identity"], ensure_ascii=False, sort_keys=True,
                                separators=(",", ":")).encode("utf-8")).hexdigest())
print("FAILURES", json.dumps(sorted(set(failures))[:10], ensure_ascii=False))
print("AUDIT_STATUS", "PASS" if not failures else "FAIL")
sys.exit(0 if not failures else 5)
AUDIT_EOF
RC=$?
echo "AUDIT_RETURN_CODE=$RC"

echo "=== EVIDENCE HASHES FOR THE NEXT CONFIG ==="
sha256sum "$CAP/evidence/source_capsule_manifest.json" "$CAP/evidence/source_capsule_manifest.sha256" "$CAP/evidence/READY.json" 2>&1
stat -c "%s %n" "$CAP/evidence/source_capsule_manifest.json" "$CAP/evidence/source_capsule_manifest.sha256" "$CAP/evidence/READY.json" 2>&1

echo "=== SUPERSEDED CAPSULE STILL UNTOUCHED ==="
echo "MODE=$(stat -c %a "$OLD")"
sha256sum "$OLD/evidence/source_capsule_manifest.json" 2>&1

if [ "$RC" -eq 0 ]; then echo TUKF09_455_CAPSULE_V3_AUDIT_PASS; else echo TUKF09_455_CAPSULE_V3_AUDIT_NONPASS; fi
