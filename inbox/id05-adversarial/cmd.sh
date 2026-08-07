#!/bin/bash
# id05-adversarial  moment audit on all 531 basins: ship the chunkable probe and launch it.
export LC_ALL=C
A=/data1/home/$USER/adv531
IN=/data1/home/$USER/hpc_mailbox/inbox/id05-adversarial
P=/data1/home/$USER/miniconda3/envs/nh_final/bin/python

cp -f $IN/run_statistical_structure_probe.py $A/src/adversarial/scripts/
cp -f $IN/adv531_moment.slurm $A/
sed -i 's/\r$//' $A/src/adversarial/scripts/run_statistical_structure_probe.py $A/adv531_moment.slurm
echo "probe md5=$(md5sum $A/src/adversarial/scripts/run_statistical_structure_probe.py | cut -c1-32) expect=b45d49568d9b06f49e295a3e0b6625b1"
$P $A/src/adversarial/scripts/run_statistical_structure_probe.py --help 2>&1 | grep -c offset | sed 's/^/  offset option present: /'

cd $A
J=$(sbatch --parsable adv531_moment.slurm 2>&1)
echo "submitted: $J"
squeue -u $USER -o "%.14i %.16j %.3t %.10M" 2>&1 | head -8
