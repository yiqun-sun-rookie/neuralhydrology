#!/bin/bash
<<<<<<< Updated upstream
export LC_ALL=C
DST=/data1/home/$USER/adv531
R=$DST/results/05_adversarial_robustness/id18_s100_hpc
echo "=== QUEUE ==="
squeue -u $USER -o "%.14i %.16j %.3t %.11M %.20R" 2>&1 | head -30
echo "running=$(squeue -u $USER -h -r -t R 2>/dev/null | wc -l)  pending=$(squeue -u $USER -h -r -t PD 2>/dev/null | wc -l)"
echo "=== SACCT ==="
sacct -S 2026-08-06T17:20 -u $USER -X --format=JobID%14,JobName%16,State%12,ExitCode%8,Elapsed%10 2>&1 | grep -E "adv531|JobID|----" | head -50
echo "=== PER-BLOCK PROGRESS (basins written / 531) ==="
for b in exp2 exp3 exp4 exp5 exp6 detect ksweep; do
  n=0
  for f in $R/${b}_531_chunk*.json; do
    [ -f "$f" ] || continue
    c=$(grep -c '\"basin\"' "$f" 2>/dev/null || echo 0)
    n=$((n + c))
  done
  printf "  %-8s %4d / 531\n" "$b" "$n"
done
if [ -d $R/l1l2_531 ]; then
  printf "  %-8s %4d / 531\n" "l1l2" "$(ls $R/l1l2_531/l1l2_records/*.npz 2>/dev/null | wc -l)"
fi
echo "=== ERRORS ==="
grep -l "Traceback\|FATAL\|CUDA out of memory" $DST/logs/adv531_*.err $DST/logs/adv531_*.out 2>/dev/null | head -8 || echo "  none"
echo "=== NEWEST LOG LINES ==="
for f in $(ls -t $DST/logs/adv531_*.out 2>/dev/null | head -4); do echo "--- $(basename $f)"; tail -2 "$f"; done
=======
# id05-adversarial  merge the 5 chunks of every block into the canonical filenames the
# analysis scripts expect, then hand the (small) JSONs back through outbox/ for local
# post-processing. Read-only with respect to the experiments; writes only new files.
export LC_ALL=C
P=/data1/home/$USER/miniconda3/envs/nh_final/bin/python
OUTBOX=/data1/home/$USER/hpc_mailbox/outbox/id05-adversarial/data

$P - <<'PY'
import json, glob, os, shutil
R = os.path.expanduser("~/adv531/results/05_adversarial_robustness/id18_s100_hpc")
M = os.path.expanduser("~/adv531/results/05_adversarial_robustness/id18_s100_merged")
os.makedirs(M, exist_ok=True)

LISTS = {
    "exp2_531": "exp2_constraint_ablation.json",
    "exp3_531": "exp3_targeted.json",
    "exp4_531": "exp4_causal.json",
    "exp5_531": "exp5_cw.json",
    "exp6_531": "exp6_yang_kge.json",
    "detect_531": "exp_detect.json",
    "ksweep_531": "ksweep.json",
}
print("=== MERGE (list-of-records blocks) ===")
for pre, name in LISTS.items():
    recs, seen = [], set()
    for f in sorted(glob.glob(os.path.join(R, f"{pre}_chunk*.json"))):
        for r in json.load(open(f)):
            if r.get("basin") in seen:
                continue
            seen.add(r.get("basin"))
            recs.append(r)
    if not recs:
        print(f"  {name:34s} MISSING"); continue
    errs = sum(1 for r in recs if "error" in r)
    json.dump(recs, open(os.path.join(M, name), "w"), indent=1)
    print(f"  {name:34s} {len(recs):4d} basins, {errs} errors, "
          f"{os.path.getsize(os.path.join(M,name))/1e6:.2f} MB")

print("=== MERGE (l1l2 summary dict) ===")
merged = {}
for f in sorted(glob.glob(os.path.join(R, "l1l2_531", "exp_l1l2_summary_eps0.1*.json"))):
    merged.update(json.load(open(f)))
name = "exp_l1l2_summary_eps0.1.json"
json.dump(merged, open(os.path.join(M, name), "w"), indent=1)
print(f"  {name:34s} {len(merged):4d} basins, "
      f"{os.path.getsize(os.path.join(M,name))/1e6:.2f} MB")
print(f"  npz records kept on HPC: {len(glob.glob(os.path.join(R,'l1l2_531','l1l2_records','*.npz')))}")

print("=== SANITY: every block must have 531 unique basins ===")
for f in sorted(glob.glob(os.path.join(M, "*.json"))):
    d = json.load(open(f))
    n = len(d) if isinstance(d, (list, dict)) else 0
    print(f"  {os.path.basename(f):34s} {n:4d} {'OK' if n == 531 else '<-- CHECK'}")
PY

echo "=== HAND BACK THROUGH OUTBOX ==="
mkdir -p $OUTBOX
cp -f /data1/home/$USER/adv531/results/05_adversarial_robustness/id18_s100_merged/*.json $OUTBOX/
cd $OUTBOX && md5sum *.json | sed 's/^/  /'
echo "  total: $(du -sh $OUTBOX | cut -f1)"
>>>>>>> Stashed changes
