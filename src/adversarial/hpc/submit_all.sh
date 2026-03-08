#!/bin/bash
# Submit all adversarial evaluation experiments
# Usage: bash src/adversarial/hpc/submit_all.sh

set -e
mkdir -p logs/05_adversarial

echo "=== Submitting adversarial full experiment ==="

JOB1=$(sbatch --parsable src/adversarial/hpc/submit_exp1_core.slurm)
echo "Exp 1 (core comparison):    job array $JOB1  [11 tasks, ~45min each]"

JOB2=$(sbatch --parsable src/adversarial/hpc/submit_exp2_constraint.slurm)
echo "Exp 2 (constraint ablation): job array $JOB2  [11 tasks, ~24min each]"

JOB3=$(sbatch --parsable src/adversarial/hpc/submit_exp3_target.slurm)
echo "Exp 3 (targeted attacks):    job array $JOB3  [11 tasks, ~8min each]"

JOB4=$(sbatch --parsable src/adversarial/hpc/submit_exp4_causal.slurm)
echo "Exp 4 (causal trigger):      job array $JOB4  [11 tasks, ~25min each]"

JOB5=$(sbatch --parsable src/adversarial/hpc/submit_exp5_cw.slurm)
echo "Exp 5 (C&W min perturb):     job array $JOB5  [20 tasks, ~33min each]"

echo ""
echo "Total: 64 SLURM tasks submitted"
echo "Estimated wall time: ~2-3 hours (all run in parallel)"
echo "Monitor: squeue -u $USER"
echo "Errors:  tail logs/05_adversarial/*.err"
