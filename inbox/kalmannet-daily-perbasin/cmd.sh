#!/usr/bin/env bash
set -o pipefail
readonly OUTPUT_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_slz_survey_development_20260928_v1"
readonly SOURCE_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916/workspace"
readonly RUNS_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916/runs"
readonly PYTHON_BIN="/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python"
readonly FAMILY="DAILY_CAMELS_KNET_ALIGNED_REMATCH_V3_20260916"
echo "SLZ_SURVEY_READ_ONLY_PREFLIGHT_V1"
echo "sequence=223"
echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "host=$(hostname)"
echo "OWN_QUEUE_BEGIN"
squeue -u "$USER" -h -o '%i|%j|%T|%P|%R|%M|%l' 2>&1 || echo "SQUEUE_FAILED"
echo "OWN_QUEUE_END"
echo "CPU_PARTITION_BEGIN"
sinfo -h -p hcpu48 -o '%P|%a|%D|%t|%C' 2>&1 || echo "SINFO_FAILED"
scontrol show partition hcpu48 2>&1 | grep -E 'PartitionName=|MaxTime=|OverSubscribe=|State=|TotalCPUs=' || echo "PARTITION_FIELDS_NOT_FOUND"
echo "CPU_PARTITION_END"
idle_nodes=$(sinfo -h -p hcpu48 -t idle -o '%D' 2>/dev/null | awk '{sum += $1} END {print sum + 0}')
echo "hcpu48_idle_nodes=$idle_nodes"
if ! [[ "$idle_nodes" =~ ^[0-9]+$ ]] || [[ "$idle_nodes" -lt 1 ]]; then
  echo "REFUSING: no idle hcpu48 node" >&2
  exit 12
fi
if [[ -d "$SOURCE_ROOT" && ! -L "$SOURCE_ROOT" ]]; then echo "SOURCE_ROOT_PRESENT=yes"; else echo "SOURCE_ROOT_PRESENT=no"; fi
if [[ -d "$RUNS_ROOT" && ! -L "$RUNS_ROOT" ]]; then echo "RUNS_ROOT_PRESENT=yes"; else echo "RUNS_ROOT_PRESENT=no"; fi
if [[ -x "$PYTHON_BIN" && ! -L "$PYTHON_BIN" ]]; then echo "PYTHON_PRESENT=yes"; else echo "PYTHON_PRESENT=no"; fi
if [[ -e "$OUTPUT_ROOT" ]]; then echo "PROPOSED_ROOT_ABSENT=no"; else echo "PROPOSED_ROOT_ABSENT=yes"; fi
PYTHONDONTWRITEBYTECODE=1 "$PYTHON_BIN" -B - "$RUNS_ROOT" "$FAMILY" <<'PY'
from hashlib import sha256
import json
from pathlib import Path
import sys

import numpy
import torch

runs_root = Path(sys.argv[1])
family = sys.argv[2]
basins = ('04105700','08190500','02102908','12447390','01487000','02178400','08070200','09513780','06803510','03076600','12175500','09035800','04027000','08109700','08086290','01440400','05503800','03049000','01435000','02092500','14185900',)
seeds = (20260824,20260901,20260908,20260915,20260922,)

def digest(path):
    value = sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()

print(f"ENVIRONMENT|python={sys.version.split()[0]}|numpy={numpy.__version__}|torch={torch.__version__.split('+')[0]}")
print("RUNS_BEGIN")
for basin in basins:
    for seed in seeds:
        run_id = f"{family}_KNET_BASIN_{basin}_SEED_{seed}"
        run_dir = runs_root / run_id
        summary_path = run_dir / "result_summary.json"
        marker_path = run_dir / "completion.marker.json"
        history_path = run_dir / "epoch_history.json"
        for path in (run_dir, summary_path, marker_path, history_path):
            if not path.exists() or path.is_symlink():
                raise SystemExit(f"ABSENT_OR_SYMLINK|{path}")
        summary_bytes = summary_path.read_bytes()
        marker_bytes = marker_path.read_bytes()
        history_bytes = history_path.read_bytes()
        summary_sha = sha256(summary_bytes).hexdigest()
        marker_sha = sha256(marker_bytes).hexdigest()
        history_sha = sha256(history_bytes).hexdigest()
        summary = json.loads(summary_bytes)
        marker = json.loads(marker_bytes)
        history = json.loads(history_bytes)
        epoch = int(summary["best_epoch"])
        checkpoint_rel = f"checkpoints/epoch_{epoch:03d}.pt"
        checkpoint = run_dir / checkpoint_rel
        if not checkpoint.is_file() or checkpoint.is_symlink():
            raise SystemExit(f"CHECKPOINT_ABSENT_OR_SYMLINK|{basin}|{seed}")
        checkpoint_sha = digest(checkpoint)
        rows = [row for row in history if int(row.get("epoch", -1)) == epoch]
        identity = summary.get("identity", {})
        if (len(rows) != 1 or summary.get("best_checkpoint") != checkpoint_rel
                or summary.get("best_checkpoint_sha256") != checkpoint_sha
                or rows[0].get("checkpoint") != checkpoint_rel
                or rows[0].get("checkpoint_sha256") != checkpoint_sha
                or marker.get("run_id") != run_id
                or marker.get("result_summary_sha256") != summary_sha
                or marker.get("epoch_history_sha256") != history_sha
                or identity.get("run_id") != run_id
                or identity.get("basin_id") != basin
                or int(identity.get("seed", -1)) != seed):
            raise SystemExit(f"IDENTITY_CHAIN_FAILED|{basin}|{seed}")
        print(f"RUN|{basin}|{seed}|summary={summary_sha}|marker={marker_sha}|history={history_sha}|"
              f"best_epoch={epoch}|best_sha={summary['best_checkpoint_sha256']}|file_sha={checkpoint_sha}")
print("RUNS_END")
print("RUN_COUNT=105")
print("PREFLIGHT_COMPLETE")
PY
