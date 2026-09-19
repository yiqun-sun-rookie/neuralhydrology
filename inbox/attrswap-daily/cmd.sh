#!/bin/bash
# seq=87 stage-3 reserve R1 (PREREG 4.2 pre-registered; user "go" 2026-09-19): cmd_r1_template3.sh d6b904beec43d426 with GEN_SHA substituted.
# Stage-3 reserve R1 (PREREG_20260916 section 4.2, pre-registered, one-off): the three registered tiers gave
# C = 0.1203 / 0.2489 / 0.3976 -> min C > 0.05 -> add sigma = 0.175 (syn_ln018), 3 seeds, +6.1 GPU h (75.2 -> 81.3 <= 100).
# Found by audit B on 2026-09-18 (the verdict had wrongly written "[0.12, 0.40] contains [0.05, 0.20]").
# Steps: install the R1 table + the config generator with --r1-only from the mailbox payload, write ONLY the four
# syn_ln018 configs (merging the manifest), submit the product gate (KIND=noise) and the 3 arms afterok(gate), append
# the V23 ledger line. The guard T16 marker already exists (CLEAN). sbatch is the only mutating operation; numeric job
# ids only. No backslash literals anywhere in this file.
set -o pipefail
date "+wallclock %F %T %z"
R=/data1/home/sunyiq/precip_swap3_daily_2026_09
PL=$HOME/hpc_mailbox/inbox/attrswap-daily/payload/pswap3
TABLE_SHA=648ab96ae4ccd391
GEN_SHA=7c6c84b897aac5ec
cd $R || exit 1
sub () {
  local out; out=$(sbatch --parsable "$@" 2>&1) || { echo "SBATCH ERROR: $out" >&2; return 1; }
  out=${out%%;*}
  case "$out" in ''|*[!0-9]*) echo "SBATCH REJECTED (no numeric id): $out" >&2; return 1;; esac
  echo "$out"
}
echo "=== A. guards ==="
case "$GEN_SHA" in "__GEN""_SHA__") echo "ABORT: GEN_SHA placeholder not substituted"; exit 1;; esac
[ -f logs/jobs.txt ] || { echo "ABORT: no prior submission"; exit 1; }
[ -f logs/guard_T16_PASS.txt ] || { echo "ABORT: guard marker missing"; exit 1; }
[ -f logs/gate_ref.txt ] || { echo "ABORT: gate_ref marker missing"; exit 1; }
grep -q "syn_ln018" logs/jobs.txt && { echo "ABORT: R1 already submitted"; exit 1; }
[ "$(ls -d runs/pswap3_syn_ln018_* 2>/dev/null | wc -l)" -eq 0 ] || { echo "ABORT: syn_ln018 run dir exists"; exit 1; }
[ -f "$PL/tables/syn_ln018_daily_529.csv.gz" ] || { echo "ABORT: R1 table missing in payload"; exit 1; }
[ -f "$PL/r1/make_pswap3_configs.py" ] || { echo "ABORT: R1 config generator missing in payload"; exit 1; }
h=$(sha256sum "$PL/tables/syn_ln018_daily_529.csv.gz" | cut -c1-16); [ "$h" = "$TABLE_SHA" ] || { echo "ABORT: table sha $h != $TABLE_SHA"; exit 1; }
g=$(sha256sum "$PL/r1/make_pswap3_configs.py" | cut -c1-16); [ "$g" = "$GEN_SHA" ] || { echo "ABORT: generator sha $g != $GEN_SHA"; exit 1; }
echo "  table $h  generator $g"
echo "=== B. install (copy, never move the originals) ==="
cp "$PL/tables/syn_ln018_daily_529.csv.gz" hpc_deploy/
cp hpc_deploy/make_pswap3_configs.py hpc_deploy/make_pswap3_configs_rev3_before_r1.py
cp "$PL/r1/make_pswap3_configs.py" hpc_deploy/make_pswap3_configs.py
cp configs/configs_manifest.json logs/configs_manifest_before_r1.json
echo "=== C. configs (login node, --r1-only) ==="
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final 2>/dev/null
python hpc_deploy/make_pswap3_configs.py --r1-only 2>&1 | tail -n 2
for c in pswap3_syn_ln018_s100 pswap3_syn_ln018_s200 pswap3_syn_ln018_s300 pswap3_smoke_syn_ln018; do [ -f configs/$c.yml ] || { echo "ABORT: config missing $c"; exit 1; }; done
echo "  configs now: $(ls configs/*.yml | wc -l) (expect 44)"
echo "  manifest entries: $(python -c "import json; m=json.load(open('configs/configs_manifest.json')); print(len(m['configs']))") (expect 44)"
echo "  unchanged sample: $(python -c "import json; a=json.load(open('logs/configs_manifest_before_r1.json'))['configs']; b=json.load(open('configs/configs_manifest.json'))['configs']; print(all(a[k]==b[k] for k in a))") (expect True)"
echo "=== D. submit gate + 3 arms ==="
g=$(sub --export=ALL,PRODUCT=syn_ln018,KIND=noise -J pswap3_gate_syn_ln018 hpc_deploy/pswap3_gate_product.slurm) || { echo "SBATCH FAILED gate"; exit 1; }
echo "gate_syn_ln018 $g kind=noise R1" | tee -a logs/jobs.txt
for s in 100 200 300; do
  j=$(sub --dependency=afterok:$g --export=ALL,CFG=pswap3_syn_ln018_s$s,GATE=guard_T16_PASS.txt:gate_syn_ln018.txt -J pswap3_syn_ln018_s$s hpc_deploy/pswap3_train.slurm) || { echo "SBATCH FAILED arm s$s"; exit 1; }
  echo "pswap3_syn_ln018_s$s $j dep=$g R1" | tee -a logs/jobs.txt
done
echo "=== E. ledger ==="
echo "R1 sigma=0.175 planned_gpu_hours 6.1 cumulative 81.3 (limit 100.0) jobs 4 $(date '+%F %T')" | tee -a logs/budget_ledger.txt
squeue -u "$USER" -o '%.10i %.36j %.9T %.10M %.9P %R' 2>&1 | grep -Ei 'pswap3|JOBID' | head -20
echo "  attrswap-daily seq now: $(cat ~/hpc_mailbox/inbox/attrswap-daily/seq 2>/dev/null)"
echo "=== DONE ==="
