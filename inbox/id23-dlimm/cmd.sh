#!/bin/bash
# id23-dlimm seq=2 : migration acceptance job on the CPU partition.
set -o pipefail
cd ~/hpc_mailbox || exit 1
mkdir -p outbox
sed -i 's/\r$//' inbox/id23-dlimm/accept.slurm

echo "=== SUBMIT ==="
JID=$(sbatch --parsable inbox/id23-dlimm/accept.slurm 2>&1)
echo "jobid=$JID"

echo "=== WAIT (max 18 min) ==="
for i in $(seq 1 108); do
    LEFT=$(squeue -j "$JID" -h -o "%i" 2>/dev/null | wc -l)
    [ $((i % 12)) -eq 0 ] && echo "t=$((i*10))s left=$LEFT"
    [ "$LEFT" -eq 0 ] && break
    sleep 10
done

echo "=== SACCT ==="
sacct -j "$JID" -X --format=JobID%12,JobName%12,NodeList%10,State%12,ExitCode%8,Elapsed%10 2>&1 | head -5

echo "=== STDOUT ==="
cat outbox/slurm_${JID}.out 2>/dev/null | tail -40 || true
echo "=== STDERR (tail) ==="
tail -15 outbox/slurm_${JID}.err 2>/dev/null || true

echo "=== KEY NUMBERS ==="
R=~/id23_dlimm/results/23_hbv_multilead_joint_uncertainty/h19_forecast_window_ceiling_throwaway_v01/forecast_window_ceiling_report.json
if [ -f "$R" ]; then
  python - "$R" <<'PY' 2>&1 | tail -20
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
s=d["arm_summary"]
for k in sorted(s): print(f"{k:30s} lead7={s[k]['mean_forecast_rmse_lead_7']:.10f}")
c=d["paired_block_contrasts_versus_frozen_base"]
r=d["paired_block_contrasts_versus_evolving_base"]
print("attribution_ceiling=%.16f" % c["frozen_base_minus_evolving_oracle_attribution_lead_7"]["point_estimate"])
print("hazard_ceiling=%.16f" % c["frozen_base_minus_evolving_oracle_hazard_lead_7"]["point_estimate"])
print("rule_space=%.16f" % r["evolving_base_minus_evolving_oracle_hazard_lead_7"]["point_estimate"])
PY
else
  echo "REPORT_MISSING"
fi
rm -f outbox/slurm_${JID}.out outbox/slurm_${JID}.err
echo "=== DONE ==="
