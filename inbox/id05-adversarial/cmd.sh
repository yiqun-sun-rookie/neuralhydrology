#!/bin/bash
# id05-adversarial  run the robustness audit (local-scale control, section 5.3) on the 531 run
export LC_ALL=C
A=/data1/home/$USER/adv531
P=/data1/home/$USER/miniconda3/envs/nh_final/bin/python
cd $A
export PYTHONPATH=$(pwd):$PYTHONPATH
$P -u src/adversarial/scripts/analyze_forcing_error_robustness_audit.py 2>&1 | tail -60
