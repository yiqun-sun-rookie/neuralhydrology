#!/bin/bash
set -o pipefail

ROOT=/data1/home/sunyiq/id30_modern_transformer_moe_20260827/repo
EXPECTED_ROOT=/data1/home/sunyiq/id30_modern_transformer_moe_20260827/repo
JOB_LIST=215314,215425,215426,215427,215428,215429

echo "=== ID30 READ-ONLY STATUS REFRESH ==="
date -Is
hostname
echo "root=$(readlink -f "$ROOT")"
if [ "$(readlink -f "$ROOT")" != "$EXPECTED_ROOT" ]; then
  echo "ROOT_MISMATCH"
  exit 1
fi

echo "=== SCHEDULER STATE ==="
squeue -j "$JOB_LIST" -o '%.18i %.12P %.28j %.8T %.10M %.30R' || true
sacct -j "$JOB_LIST" -n -P --format=JobID,JobName,Partition,State,ExitCode,Elapsed,NodeList,MaxRSS || true

echo "=== REGISTERED DEVELOPMENT STATE ==="
cd "$ROOT" || exit 1
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh || exit 1
conda activate nh_final || exit 1
python -m src.modern_transformer_moe.scripts.inspect_development_runs --all || true

echo "=== HASH-BOUND INTERNAL-VALIDATION ARTIFACTS ==="
python - "$ROOT" <<'PY'
import csv
import hashlib
import json
import sys
from pathlib import Path

from ruamel.yaml import YAML

root = Path(sys.argv[1]).resolve()


def safe_path(relative):
    if not relative or relative in {"not_bound", "not_applicable"}:
        return None
    path = (root / relative).resolve()
    path.relative_to(root)
    return path


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


bindings_path = root / "src/modern_transformer_moe/registry/development_run_bindings.json"
bindings = json.loads(bindings_path.read_text(encoding="utf-8"))
summaries = []
for role in ("B01", "D01", "D02", "D03", "M01"):
    matches = [r for r in bindings.get("records", []) if r.get("role") == role and r.get("seed") == 100]
    if len(matches) != 1:
        summaries.append({"role": role, "binding_count": len(matches)})
        continue
    record = matches[0]
    item = {
        "role": role,
        "seed": 100,
        "status": record.get("status"),
        "run_id": record.get("run_id"),
        "run_dir": record.get("run_dir"),
        "metrics_artifact_path": record.get("metrics_artifact_path"),
        "recorded_metrics_artifact_sha256": record.get("metrics_artifact_sha256"),
        "failure_stage": record.get("failure_stage"),
        "failure_reason": record.get("failure_reason"),
    }
    artifact_path = safe_path(record.get("metrics_artifact_path"))
    if artifact_path is not None and artifact_path.is_file():
        item["actual_metrics_artifact_sha256"] = sha256(artifact_path)
        artifact = json.loads(artifact_path.read_text(encoding="utf-8"))
        for key in (
            "epoch", "metric", "median_nse", "selection_period", "checkpoint_path", "checkpoint_sha256",
            "validation_metrics_path", "validation_metrics_sha256", "validation_results_path",
            "validation_results_sha256", "run_config_path", "run_config_sha256",
        ):
            if key in artifact:
                item[key] = artifact[key]
    summaries.append(item)

print(json.dumps({
    "bindings_path": str(bindings_path.relative_to(root)),
    "bindings_sha256": sha256(bindings_path),
    "records": summaries,
}, indent=2, sort_keys=True))

selection_path = root / "results/30_modern_transformer_moe/dense_selection_report.json"
if selection_path.is_file():
    selection = json.loads(selection_path.read_text(encoding="utf-8"))
    print(json.dumps({
        "selection_report_path": str(selection_path.relative_to(root)),
        "selection_report_sha256": sha256(selection_path),
        "selected_experiment_id": selection.get("selected_experiment_id"),
        "selected_config_path": selection.get("selected_config_path"),
        "selected_config_sha256": selection.get("selected_config_sha256"),
        "candidate_metrics": selection.get("candidate_metrics"),
        "selection_epoch": selection.get("selection_epoch"),
        "selection_metric": selection.get("selection_metric"),
        "selection_period": selection.get("selection_period"),
        "selection_rule": selection.get("selection_rule"),
    }, indent=2, sort_keys=True))
else:
    print(json.dumps({"selection_report": "ABSENT"}, sort_keys=True))

gate_path = root / "results/30_modern_transformer_moe/single_seed_dense_gate.json"
if gate_path.is_file():
    print(json.dumps({
        "single_seed_gate_path": str(gate_path.relative_to(root)),
        "single_seed_gate_sha256": sha256(gate_path),
        "gate": json.loads(gate_path.read_text(encoding="utf-8")),
    }, indent=2, sort_keys=True))
else:
    print(json.dumps({"single_seed_gate": "ABSENT"}, sort_keys=True))

selected_config_path = root / "src/modern_transformer_moe/configs/moe_selected_s100.yml"
if selected_config_path.is_file():
    config = YAML(typ="safe").load(selected_config_path.read_text(encoding="utf-8"))
    keys = (
        "experiment_name", "model", "seed", "transformer_nlayers", "transformer_nheads",
        "transformer_dim_feedforward", "transformer_moe_first_layer", "transformer_moe_num_experts",
        "transformer_moe_top_k", "transformer_moe_shared_dim", "transformer_moe_routed_dim",
        "batch_size", "learning_rate", "epochs", "seq_length",
    )
    print(json.dumps({
        "generated_m01_config_path": str(selected_config_path.relative_to(root)),
        "generated_m01_config_sha256": sha256(selected_config_path),
        "selected_fields": {key: config.get(key) for key in keys if key in config},
    }, indent=2, sort_keys=True))
else:
    print(json.dumps({"generated_m01_config": "ABSENT"}, sort_keys=True))

registry_path = root / "src/modern_transformer_moe/registry/experiments.csv"
with registry_path.open(newline="", encoding="utf-8") as handle:
    rows = [row for row in csv.DictReader(handle) if row.get("experiment_id") in {"B01", "D01", "D02", "D03", "M01"}]
print(json.dumps({
    "experiment_registry_path": str(registry_path.relative_to(root)),
    "experiment_registry_sha256": sha256(registry_path),
    "rows": rows,
}, indent=2, sort_keys=True))

for record in summaries:
    if record.get("role") != "M01" or record.get("status") != "COMPLETE":
        continue
    run_dir = safe_path(record.get("run_dir"))
    diagnostic = run_dir / "router_diagnostics_epoch030.json" if run_dir else None
    print(json.dumps({
        "router_diagnostics_path": str(diagnostic.relative_to(root)) if diagnostic and diagnostic.is_file() else "ABSENT",
        "router_diagnostics_sha256": sha256(diagnostic) if diagnostic and diagnostic.is_file() else "ABSENT",
    }, indent=2, sort_keys=True))
PY

echo "=== READ-ONLY REFRESH COMPLETE ==="
date -Is
