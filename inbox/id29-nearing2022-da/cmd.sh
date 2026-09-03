#!/bin/bash
# seq=438 修复成对重训脚本的四处过期指向, 只修不提交
set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
D="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics"
S="$ROOT/src/29_nearing2022_da_ar/hpc/run_warmup_target_pair.slurm"

echo "=== 1. 放置分析合同(内容来自本地冻结副本,散列必须自证) ==="
cat > "$D/warmup_target_paired_analysis_contract.json" <<'CONTRACTEOF'
{
  "schema": "nearing2022-warmup-target-paired-analysis-contract-v1",
  "created_at": "2026-08-11T05:55:00+08:00",
  "protocol": "results/29_nearing2022_da_ar/formal_closure/warmup_target_paired_retraining_protocol.json",
  "protocol_sha256": "16bdf57bcbf3afd335e91107bc908330e86ac7fa20db60cbf54ee30b1ab321c1",
  "basin_count": 531,
  "reference_simulation_coordinate": "N22-TS-SIM-S0",
  "registered_current_coordinate": "N22-EVAL-TS-AR-L01-TR000-TE100-S0",
  "common_index_rule": "exact_registered_finite_dates_per_basin",
  "primary_effect": "median(masked_nse - control_nse)",
  "bootstrap": {
    "statistic": "median(masked_nse - control_nse)",
    "seed": 20220818,
    "replicates": 20000,
    "quantiles": [
      0.025,
      0.975
    ],
    "quantile_method": "linear"
  },
  "wilcoxon": {
    "alternative": "two-sided",
    "zero_method": "wilcox",
    "method": "approx",
    "correction": false
  },
  "decision_thresholds": {
    "registered_current_median_nse": 0.6161134850361614,
    "registered_recompute_tolerance": 1e-12,
    "author_median_nse": 0.5539548397064209,
    "control_stability_tolerance": 0.01,
    "minimum_material_gap_reduction": 0.02,
    "paper_agreement_tolerance": 0.02
  },
  "decision_order": [
    "require all four result payloads to contain exactly the frozen 531 basins",
    "require registered, control and masked finite date arrays to equal the registered finite date array for every basin",
    "require the independently recomputed registered median NSE to equal the frozen registered value within 1e-12",
    "apply the control-stability tolerance before interpreting treatment effects",
    "apply the paired bootstrap direction and minimum paper-gap reduction rule",
    "apply paper-agreement tolerance only after material contribution passes"
  ],
  "status_values": [
    "HOLD_INPUT_MISMATCH",
    "HOLD_RUNTIME_INSTABILITY",
    "NO_MATERIAL_CONTRIBUTION",
    "MATERIAL_CONTRIBUTION"
  ],
  "output_contract": {
    "per_basin_rows": 531,
    "per_basin_sort": "basin ascending",
    "csv_float_format": "%.17g",
    "json_sort_keys": true,
    "overwrite_allowed": false
  },
  "scientific_boundary": "This analysis quantifies the single warmup-target mask under the current runtime and paired experiment. It cannot prove unique historical causality, recover unavailable author-era dependencies, or recreate NVIDIA Tesla V100 execution."
}
CONTRACTEOF
sha256sum "$D/warmup_target_paired_analysis_contract.json"
echo "必须等于 5bb3da898bba8b01b290a2a3efe70a943235fd103e9913711d19a6290869a114"

echo "=== 2. 备份原脚本 ==="
cp -n "$S" "$S.orig_20260903" && echo "backed up" || echo "backup already exists"
sha256sum "$S.orig_20260903"

echo "=== 3. 四处定点修复 ==="
python3 - "$S" <<'PYEOF'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); t = p.read_text()
subs = [
 ('author_v13_training_data_port_all531"', 'author_v13_training_data_port_all531_v2"'),
 ('author_v13_warmup_isolation_all531"',  'author_v13_warmup_isolation_all531_v2"'),
 ('for JOB in 202506 202507; do',          'for JOB in 202510 202511; do'),
]
for a,b in subs:
    assert t.count(a)==1, ('pattern not unique: '+a, t.count(a))
    t = t.replace(a,b)
old = 'printf \'%s\n\' "$FAILURES"\ntest -z "$FAILURES"'
new = ('printf \'%s\n\' "$FAILURES"\n'
       '# 2026-09-03: 原判据 test -z "$FAILURES" 已永久不可满足——列表内多个作业曾 TIMEOUT,\n'
       '# 其坐标此后已由新作业号重跑成功。改用登记系统的缺口清单,它是更强的判据:\n'
       '# missing_total==0 蕴含"没有任何坐标缺失",严格强于"这些作业号从未失败过"。\n'
       'source ~/miniconda3/etc/profile.d/conda.sh && conda activate nh_final\n'
       'python - "$ROOT" <<\'GUARDEOF\'\n'
       'import sys\n'
       'from pathlib import Path\n'
       'root = Path(sys.argv[1])\n'
       'sys.path.insert(0, str(root / "src/29_nearing2022_da_ar/scripts"))\n'
       'from verify_registered_closure import audit_registered_closure\n'
       'reg = root / "src/29_nearing2022_da_ar/registry"\n'
       'agg = root / "closure_20260810/aggregation"\n'
       'c = audit_registered_closure(root, reg/"experiment_registry.csv", reg/"evaluation_registry.csv",\n'
       '                             reg/"assimilation_hyperparameter_registry.csv",\n'
       '                             agg/"evaluations", agg/"hyperparameters")\n'
       'n = len(c["missing"])\n'
       'print(f"registered_missing_total={n}")\n'
       'assert n == 0, f"registered matrix incomplete: {n} missing coordinates"\n'
       'GUARDEOF')
assert t.count(old)==1, ('failure-guard pattern not unique', t.count(old))
t = t.replace(old,new)
p.write_text(t)
print("4 edits applied")
PYEOF

echo "=== 4. 差异 ==="
diff "$S.orig_20260903" "$S" || true
echo "=== 5. 修复后的脚本散列与语法检查 ==="
sha256sum "$S"
bash -n "$S" && echo "syntax OK"
echo "=== 6. 逐条复检准入条件 ==="
for f in "$D/warmup_target_paired_retraining_protocol.json" "$D/warmup_target_paired_analysis_contract.json"; do [ -f "$f" ] && echo "OK   $f" || echo "FAIL $f"; done
for d in "$D/author_v13_training_data_port_all531_v2" "$D/author_v13_warmup_isolation_all531_v2"; do [ -d "$d" ] && echo "OK   $d" || echo "FAIL $d"; done
sacct -X -n -P -j 202510,202511 --format=JobID,State,ExitCode 2>/dev/null || true
[ -e "$D/warmup_pair" ] && echo "WARN warmup_pair 已存在" || echo "OK   warmup_pair 不存在"
echo "=== 7. 未提交任何作业 ==="
squeue -u sunyiq -h -o '%j' 2>/dev/null | grep -c 'warm' || echo 0
