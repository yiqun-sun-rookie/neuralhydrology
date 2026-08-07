#!/bin/bash
# id05-adversarial  run the two npz-based analyses on the new 531 records and hand the
# summaries back. Pure CPU post-processing on already-computed results; no GPU, no rerun.
export LC_ALL=C
A=/data1/home/$USER/adv531
M=$A/results/05_adversarial_robustness/id18_s100_merged
OUTBOX=/data1/home/$USER/hpc_mailbox/outbox/id05-adversarial/data
P=/data1/home/$USER/miniconda3/envs/nh_final/bin/python

# the analysis scripts hardcode results/.../id18_s100, so stage the new run there
echo "=== STAGE ==="
S=$A/results/05_adversarial_robustness/id18_s100
mkdir -p $S
cp -f $M/*.json $S/
ln -sfn $A/results/05_adversarial_robustness/id18_s100_hpc/l1l2_531/l1l2_records $S/l1l2_records
echo "  staged json: $(ls $S/*.json | wc -l)   npz visible: $(ls -L $S/l1l2_records/*.npz 2>/dev/null | wc -l)"

cd $A
export PYTHONPATH=$(pwd):$PYTHONPATH

echo "=== L1 attribution (leave-one-variable-out by snow group) ==="
$P -u src/adversarial/scripts/analyze_l1_attribution.py 2>&1 | tail -25

echo "=== L2 signatures (flood peaks, water balance) ==="
$P -u src/adversarial/scripts/analyze_l2_signatures.py 2>&1 | tail -30

echo "=== HAND BACK ==="
mkdir -p $OUTBOX
cp -f $S/l1_attribution_summary.csv $S/l2_signatures_summary.csv $OUTBOX/ 2>/dev/null
cd $OUTBOX && md5sum *.csv 2>/dev/null | sed 's/^/  /'
wc -l *.csv 2>/dev/null | sed 's/^/  /'
