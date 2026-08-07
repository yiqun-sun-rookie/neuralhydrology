#!/bin/bash
# id05-adversarial seq=24: ship the 531-basin structure-audit summary back through the outbox.
export LC_ALL=C
A=/data1/home/$USER/adv531
R=$A/results/05_adversarial_robustness/id18_s100
M=/data1/home/$USER/hpc_mailbox

echo "=== TIME ==="
date

cd $M || exit 1
mkdir -p outbox/id05-adversarial/data
cp -f $R/statistical_structure_summary_eps0.1.csv outbox/id05-adversarial/data/

echo "=== SHIPPED ==="
ls -l outbox/id05-adversarial/data/statistical_structure_summary_eps0.1.csv
md5sum outbox/id05-adversarial/data/statistical_structure_summary_eps0.1.csv
wc -l outbox/id05-adversarial/data/statistical_structure_summary_eps0.1.csv
head -1 outbox/id05-adversarial/data/statistical_structure_summary_eps0.1.csv
