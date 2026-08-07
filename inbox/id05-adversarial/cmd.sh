#!/bin/bash
# id05-adversarial  ship the occlusion table (unchanged, already 531 in the manuscript)
# and rerun the robustness audit for the section 5.3 local-scale numbers.
export LC_ALL=C
A=/data1/home/$USER/adv531
S=$A/results/05_adversarial_robustness/id18_s100
MB=/data1/home/$USER/hpc_mailbox
P=/data1/home/$USER/miniconda3/envs/nh_final/bin/python

cp -f $MB/payload/occlusion_importance_shuffle.csv $S/
echo "occlusion md5=$(md5sum $S/occlusion_importance_shuffle.csv | cut -c1-32) expect=1093d4ade1306c1aff756d71acad9a08"

cd $A
export PYTHONPATH=$(pwd):$PYTHONPATH
$P -u src/adversarial/scripts/analyze_forcing_error_robustness_audit.py 2>&1 | tail -55
