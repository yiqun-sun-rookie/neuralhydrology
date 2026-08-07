#!/bin/bash
# id05-adversarial  run the manuscript's own analysis scripts on the 531 results, so the
# revised numbers come from the same code that produced the published ones.
export LC_ALL=C
A=/data1/home/$USER/adv531
S=$A/results/05_adversarial_robustness/id18_s100
OUTBOX=/data1/home/$USER/hpc_mailbox/outbox/id05-adversarial/data
P=/data1/home/$USER/miniconda3/envs/nh_final/bin/python
cd $A
export PYTHONPATH=$(pwd):$PYTHONPATH

echo "=== A. hydro vulnerability (feeds the cross-analysis) ==="
$P -u src/adversarial/scripts/analyze_hydro_vulnerability.py 2>&1 | tail -18

echo
echo "=== B. constraint x snow cross-analysis  (section 4.3 numbers) ==="
$P -u src/adversarial/scripts/analyze_statistical_constraint_snow_cross.py 2>&1 | tail -45

echo
echo "=== C. snow amplification (section 5.3 local-scale control) ==="
$P -u src/adversarial/scripts/analyze_snow_amplification.py 2>&1 | tail -25

echo
echo "=== HAND BACK ==="
mkdir -p $OUTBOX
cp -f $S/hydro_vulnerability_summary.csv $OUTBOX/ 2>/dev/null
find $S -maxdepth 2 -name "*.csv" -newermt "-20 minutes" 2>/dev/null | head -10 | sed 's/^/  new: /'
cd $OUTBOX && ls -l *.csv | awk '{print "  "$5, $9}'
