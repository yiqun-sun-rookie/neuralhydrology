set -o pipefail
# READ-ONLY dry run (seq 735): does validate_entry_gates pass on the v2 receipts once only the job IDs change?
# Copies the preparer to a scratch dir outside ROOT; writes nothing under ROOT; submits nothing.
ROOT=/data1/home/sunyiq/nearing2022_da
D="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics"
T=$HOME/tmp_id29_dryrun_735; mkdir -p "$T"
sed -e 's/"202506"/"202510"/' -e 's/"202507"/"202511"/' "$ROOT/src/29_nearing2022_da_ar/scripts/prepare_warmup_target_pair.py" > "$T/prep_ids_only.py"
grep -n 'slurm_job_id' "$T/prep_ids_only.py"
source ~/miniconda3/etc/profile.d/conda.sh; conda activate nh_final
echo "=== receipts ==="
cat "$D/author_v13_training_data_port_all531_v2/diagnostic_receipt.json"; echo
cat "$D/author_v13_warmup_isolation_all531_v2/diagnostic_receipt.json"; echo
echo "=== dry run ==="
cd "$T" && timeout 300 python - "$ROOT" "$D" <<'PY'
import sys, json, traceback, importlib.util
root, d = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("p", "prep_ids_only.py"); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
for name in ("author_v13_training_data_port_all531_v2", "author_v13_warmup_isolation_all531_v2"):
    a = json.load(open(f"{d}/{name}/audit.json"))
    print(name, "audit top keys:", sorted(a)[:30])
    for k in ("scope", "inputs", "source", "raw_targets_after_inverse_scaling", "raw_targets_before_normalization", "target_scaler", "author_vs_current_masked", "one_factor_contract", "source_binding", "conclusion"):
        if k in a and isinstance(a[k], dict): print("  ", k, "->", json.dumps(a[k])[:400])
try:
    r = m.validate_entry_gates(root, f"{root}/results/29_nearing2022_da_ar/formal_closure/warmup_target_paired_retraining_protocol.json",
                               f"{d}/author_v13_training_data_port_all531_v2", f"{d}/author_v13_warmup_isolation_all531_v2")
    print("ENTRY_GATES_PASS", json.dumps(r)[:600])
except Exception as e:
    print("ENTRY_GATES_FAIL", type(e).__name__, e)
PY
rm -rf "$T"
exit 0
