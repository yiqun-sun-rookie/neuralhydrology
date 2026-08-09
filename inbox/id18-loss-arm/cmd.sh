#!/bin/bash
# ID18 seq=29: read-only final artifact, hash, decision, and independent-audit verification.
set -eo pipefail

TARGET=/data1/home/sunyiq/id18_e04_20260809
RESULT=$TARGET/results/18_lstm_fair_531/E04_daymet_post2008_objective_confirmation_482
ANALYSIS=$RESULT/analysis_confirmation_20260809
AUDIT=$RESULT/audit/e04_independent_recomputation.json
JOBS=202071,202072,202073,202074,202075,202076,202077,202078,202079,202080,202081,202082,202083

echo "=== TIMESTAMP ==="
date -Is
echo "=== FINAL_JOB_STATUS ==="
sacct -X -j "$JOBS" --format=JobID,JobName%28,State,Elapsed,ExitCode,NodeList,AllocCPUS,AllocTRES%36,Start,End -P 2>&1
echo "=== SCORE_LOG ==="
cat "$TARGET/logs/score-202083.out" 2>&1
echo "=== ERROR_LOG_SIZES ==="
stat -c '%n size=%s' "$TARGET"/logs/conceptual-{202071,202072,202073,202074,202075,202076}.err \
    "$TARGET"/logs/neural-{202077,202078,202079,202080,202081,202082}.err \
    "$TARGET/logs/score-202083.err" 2>&1
echo "=== COMPLETION_FILES ==="
find "$RESULT/conceptual" -path '*/completion.json' -type f -print | sort
find "$RESULT/protocol/neural_completions" -name '*.json' -type f -print | sort
echo "=== DERIVED_FILES ==="
find "$ANALYSIS" -maxdepth 1 -type f -printf '%f size=%s\n' | sort
stat -c '%n size=%s' "$AUDIT"

source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final
export E04_TARGET="$TARGET"
echo "=== INDEPENDENT_ARTIFACT_CHECK ==="
python - <<'PY'
import csv
import hashlib
import json
import os
from pathlib import Path

target = Path(os.environ["E04_TARGET"])
result = target / "results/18_lstm_fair_531/E04_daymet_post2008_objective_confirmation_482"
analysis = result / "analysis_confirmation_20260809"
code = target

def load(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))

def sha(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()

experiment = "E04_daymet_post2008_objective_confirmation_482"
contract_path = code / "src/loss_mechanism_531/configs/e04_daymet_confirmation_contract.json"
basin_path = code / "src/loss_mechanism_531/configs/e04_daymet_confirmation_basins.txt"
source_basin_path = code / "src/xaj_global_pilot/configs/conceptual_benchmark_camels_us_531_repro.txt"
contract = load(contract_path)
preflight = load(result / "protocol/preflight.json")
manifest = load(analysis / "analysis_manifest.json")
decision = load(analysis / "decision.json")
audit = load(result / "audit/e04_independent_recomputation.json")

assert contract["experiment_id"] == experiment
assert preflight["experiment_id"] == experiment
assert manifest["experiment_id"] == experiment
assert audit["experiment_id"] == experiment
contract_hash = sha(contract_path)
basin_hash = sha(basin_path)
source_basin_hash = sha(source_basin_path)
assert contract_hash == preflight["contract_sha256"] == manifest["contract_sha256"] == audit["contract_sha256"]
assert basin_hash == contract["frozen_hashes"]["basin_manifest_sha256"] == preflight["basin_manifest_sha256"]
assert source_basin_hash == contract["frozen_hashes"]["source_basin_manifest_sha256"] == preflight["source_basin_manifest_sha256"]
assert load(result / "protocol/e04_daymet_confirmation_contract.json") == contract

source_hashes = {}
for item in preflight["source_files"]:
    path = code / item["path"]
    actual = sha(path)
    assert actual == item["sha256"], (item["path"], actual, item["sha256"])
    source_hashes[item["path"]] = actual

generated_hashes = {}
for item in preflight["generated_configs"]:
    path = result / item["path"]
    actual = sha(path)
    assert actual == item["sha256"], (item["path"], actual, item["sha256"])
    generated_hashes[str(path.resolve())] = actual

conceptual = []
for arm in ("nse", "flow_regime_nse"):
    for model in ("gr4j", "xaj", "hbv_lite"):
        path = result / "conceptual" / arm / model / "completion.json"
        item = load(path)
        assert item["experiment_id"] == experiment
        assert item["model"] == model and item["loss_arm"] == arm
        assert item["basin_count"] == 482
        assert item["contract_sha256"] == contract_hash
        assert item["basin_manifest_sha256"] == basin_hash
        conceptual.append(str(path))
assert len(conceptual) == 6

prediction_hashes = {item["path"]: item["sha256"] for item in manifest["prediction_files"]}
assert len(prediction_hashes) == 6
neural = []
expected_integrity = {
    "basin_count": 482,
    "date_count": 2191,
    "start_date": "2009-01-01",
    "end_date": "2014-12-31",
    "all_simulations_finite": True,
}
for arm in ("nse", "flow_regime_nse"):
    for seed in (100, 200, 300):
        path = result / "protocol/neural_completions" / f"{arm}_s{seed}.json"
        item = load(path)
        assert item["experiment_id"] == experiment
        assert item["arm"] == arm and item["seed"] == seed and item["epoch"] == 30
        assert item["non_scientific_smoke"] is False
        assert item["integrity"] == expected_integrity
        config_path = str(Path(item["config_path"]).resolve())
        prediction_path = str(Path(item["prediction_path"]).resolve())
        assert Path(config_path).is_file() and sha(config_path) == item["config_sha256"]
        assert generated_hashes[config_path] == item["config_sha256"]
        assert Path(prediction_path).is_file()
        assert prediction_hashes[prediction_path] == item["prediction_sha256"]
        neural.append(str(path))
assert len(neural) == 6

assert manifest["basin_count"] == 482
assert manifest["arms"] == ["nse", "flow_regime_nse"]
assert set(manifest["models"]) == {"gr4j", "xaj", "hbv_lite", "lstm_three_seed_ensemble"}
output_hashes = {}
for name, expected in manifest["outputs"].items():
    actual = sha(analysis / name)
    assert actual == expected, (name, actual, expected)
    output_hashes[name] = actual
assert manifest["decision"] == decision

assert audit["audit_status"] == "PASS"
assert audit["tolerance"] == 1e-10
for name, item in audit["comparisons"].items():
    assert item["passed"] is True, (name, item)
    assert float(item["maximum_numeric_difference"]) <= float(audit["tolerance"]), (name, item)
assert audit["formal_decision"] == decision
assert audit["recomputed_decision"]["verdict"] == decision["verdict"]

with (analysis / "criterion_summary.csv").open("r", encoding="utf-8", newline="") as handle:
    criteria = list(csv.DictReader(handle))

summary = {
    "artifact_check": "PASS",
    "experiment_id": experiment,
    "job_completion_count": 13,
    "conceptual_completion_count": len(conceptual),
    "neural_completion_count": len(neural),
    "source_file_hash_count": len(source_hashes),
    "generated_config_hash_count": len(generated_hashes),
    "contract_sha256": contract_hash,
    "basin_manifest_sha256": basin_hash,
    "source_basin_manifest_sha256": source_basin_hash,
    "analysis_output_hashes": output_hashes,
    "audit_file_sha256": sha(result / "audit/e04_independent_recomputation.json"),
    "decision": decision,
    "criterion_summary": criteria,
    "audit_status": audit["audit_status"],
    "audit_comparisons": audit["comparisons"],
}
print(json.dumps(summary, ensure_ascii=False, indent=2))
PY
