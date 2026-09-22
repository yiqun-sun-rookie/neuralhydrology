#!/usr/bin/env bash
# sequence=186
# One authorized metadata-only probe. No scheduler submission or model computation.
set -euo pipefail

readonly SEQUENCE=186
readonly SOURCE_ROOT=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916
readonly PROPOSED_ROOT=/data1/home/sunyiq/kalmannet_daily_camels_state_update_control_20260921_v1
readonly PYTHON_BIN=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python

echo READONLY_STAGE2A_PROBE_V1
echo "sequence=$SEQUENCE"
echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "host=$(hostname)"

echo OWN_QUEUE_BEGIN
if timeout 20s squeue -u "$USER" -h -o '%i|%j|%T|%P|%N|%R|%M|%l'; then
  echo OWN_QUEUE_STATUS=PASS
else
  echo OWN_QUEUE_STATUS=ERROR
fi
echo OWN_QUEUE_END

echo CPU_PARTITION_BEGIN
if timeout 20s sinfo -p hcpu48 -h -o '%P|%a|%l|%D|%t|%C'; then
  echo CPU_PARTITION_STATUS=PASS
else
  echo CPU_PARTITION_STATUS=ERROR
fi
if timeout 20s scontrol show partition hcpu48 | grep -E 'PartitionName=|State=|OverSubscribe=|TotalCPUs=|TotalNodes='; then
  echo CPU_PARTITION_RULES_STATUS=PASS
else
  echo CPU_PARTITION_RULES_STATUS=ERROR
fi
echo CPU_PARTITION_END

echo PROPOSED_ROOT_BEGIN
if [[ -e "$PROPOSED_ROOT" || -L "$PROPOSED_ROOT" ]]; then
  echo PROPOSED_ROOT_ABSENT=no
else
  echo PROPOSED_ROOT_ABSENT=yes
fi
echo PROPOSED_ROOT_END

echo SELECTED_CHECKPOINTS_BEGIN
timeout 120s "$PYTHON_BIN" -B - "$SOURCE_ROOT" <<'PY'
import hashlib
import json
from pathlib import Path
import re
import sys

source_lexical = Path(sys.argv[1])
banned = "formal-evaluation"
if banned in str(source_lexical).casefold():
    raise PermissionError("forbidden source path")
source = source_lexical.resolve(strict=True)
if banned in str(source).casefold():
    raise PermissionError("forbidden resolved source path")
runs = (source / "runs").resolve(strict=True)
if banned in str(runs).casefold() or not runs.is_relative_to(source):
    raise PermissionError("run root outside approved source")

family = "DAILY_CAMELS_KNET_ALIGNED_REMATCH_V3_20260916"
schema = "daily_camels_knet_aligned_rematch_v3"
seeds = (20260824, 20260901, 20260908, 20260915, 20260922)
expected_network = {
    20260824: (151, "dba62964dc897f282db80eddba93aa163ced1c248d60ec4f0ac6a7254d76b666"),
    20260901: (80, "c8e4fb2baf47bb92324cd7760609d9e1a06ac934275ddf5b1c3a809219ffbe8c"),
    20260908: (178, "f69b3068c08e14aa17495a618a7827f4218d608126624a65dfc7dab181a2a7ee"),
    20260915: (124, "465a5fe8cbae21beec06324e64127b36cd9eeadec68d285d547b03d4fbfd6dd5"),
    20260922: (134, "ba99d913dad8365a607702684e190ec38d46085cc301d5bc84469897f73e87d7"),
}

def inside_file(path, root):
    if banned in str(path).casefold():
        raise PermissionError("forbidden lexical file path")
    resolved = path.resolve(strict=True)
    if banned in str(resolved).casefold() or not resolved.is_relative_to(root):
        raise PermissionError("file resolves outside its approved run")
    if not resolved.is_file():
        raise ValueError("expected regular file is absent")
    return resolved

def small_json(path, root):
    resolved = inside_file(path, root)
    size = resolved.stat().st_size
    if size > 1_000_000:
        raise ValueError("metadata file exceeds one megabyte")
    content = resolved.read_bytes()
    return json.loads(content), hashlib.sha256(content).hexdigest(), size

errors = 0
for arm in ("knet", "ukf"):
    for seed in seeds:
        run_id = f"{family}_{arm.upper()}_BASIN_02092500_SEED_{seed}"
        record = {"arm": arm, "seed": seed, "run_id": run_id}
        try:
            run_lexical = runs / run_id
            if banned in str(run_lexical).casefold():
                raise PermissionError("forbidden run path")
            run = run_lexical.resolve(strict=True)
            if banned in str(run).casefold() or not run.is_relative_to(runs):
                raise PermissionError("run resolves outside approved runs")
            summary, summary_sha, summary_size = small_json(run / "result_summary.json", run)
            marker, marker_sha, marker_size = small_json(run / "completion.marker.json", run)
            identity = summary.get("identity")
            if not isinstance(identity, dict):
                raise ValueError("summary identity missing")
            required = {
                "experiment_family": family,
                "schema_version": schema,
                "run_id": run_id,
                "arm": arm,
                "basin_id": "02092500",
                "seed": seed,
                "state_dimension": 11,
            }
            for key, value in required.items():
                if identity.get(key) != value:
                    raise ValueError(f"identity mismatch: {key}")
            if summary.get("schema_version") != schema or summary.get("experiment_family") != family or summary.get("arm") != arm:
                raise ValueError("summary family, schema, or arm mismatch")
            if marker.get("run_id") != run_id or marker.get("result_summary_sha256") != summary_sha:
                raise ValueError("completion marker does not bind summary")
            if summary.get("stop_reason") not in ("EARLY_STOP", "CEILING"):
                raise ValueError("selected run did not end in an accepted state")
            epoch = summary.get("best_epoch")
            if type(epoch) is not int or not 0 <= epoch <= 200:
                raise ValueError("best epoch outside fixed budget")
            relative = summary.get("best_checkpoint")
            match = re.fullmatch(r"checkpoints/epoch_(\d{3})\.pt", relative or "")
            if not match or int(match.group(1)) != epoch:
                raise ValueError("best checkpoint path disagrees with epoch")
            registered_sha = summary.get("best_checkpoint_sha256")
            if not isinstance(registered_sha, str) or re.fullmatch(r"[0-9a-fA-F]{64}", registered_sha) is None:
                raise ValueError("best checkpoint checksum missing or malformed")
            checkpoint = inside_file(run / relative, run)
            if arm == "knet" and (epoch, registered_sha.lower()) != expected_network[seed]:
                raise ValueError("network selection differs from frozen plan")
            record.update({
                "status": "SUMMARY_AND_PATH_VERIFIED_CONTENT_NOT_HASHED",
                "best_epoch": epoch,
                "stop_reason": summary["stop_reason"],
                "best_checkpoint": relative,
                "registered_checkpoint_sha256": registered_sha.lower(),
                "checkpoint_size_bytes": checkpoint.stat().st_size,
                "summary_size_bytes": summary_size,
                "summary_sha256": summary_sha,
                "marker_size_bytes": marker_size,
                "marker_sha256": marker_sha,
                "matrix_sha256": identity.get("matrix_sha256"),
                "frozen_manifest_sha256": identity.get("frozen_members_manifest_sha256"),
                "contract_sha256": identity.get("contract_sha256"),
                "code_sha256": identity.get("aligned_rematch_code_sha256"),
                "actual_checkpoint_sha256_verified": False,
            })
        except (OSError, ValueError, TypeError, KeyError, PermissionError) as error:
            errors += 1
            record.update({"status": "ERROR", "error": str(error)})
        print(json.dumps(record, sort_keys=True, ensure_ascii=True))
print(f"CHECKPOINT_RECORDS=10")
print(f"CHECKPOINT_ERRORS={errors}")
if errors:
    raise SystemExit(20)
PY
echo SELECTED_CHECKPOINTS_END
