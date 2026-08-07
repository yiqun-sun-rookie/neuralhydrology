#!/bin/bash
# id05-adversarial  merge the 5 chunks of every block into the canonical filenames the
# analysis scripts expect, then hand the (small) JSONs back through outbox/ for local
# post-processing. Writes only new files; touches no experiment output.
export LC_ALL=C
P=/data1/home/$USER/miniconda3/envs/nh_final/bin/python
OUTBOX=/data1/home/$USER/hpc_mailbox/outbox/id05-adversarial/data

$P - <<'PY'
import json, glob, os
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
    for f in sorted(glob.glob(os.path.join(R, pre + "_chunk*.json"))):
        for r in json.load(open(f)):
            b = r.get("basin")
            if b in seen:
                continue
            seen.add(b)
            recs.append(r)
    if not recs:
        print("  %-34s MISSING" % name)
        continue
    errs = sum(1 for r in recs if "error" in r)
    p = os.path.join(M, name)
    json.dump(recs, open(p, "w"), indent=1)
    print("  %-34s %4d basins, %d errors, %.2f MB" % (name, len(recs), errs, os.path.getsize(p) / 1e6))

print("=== MERGE (l1l2 summary dict) ===")
merged = {}
for f in sorted(glob.glob(os.path.join(R, "l1l2_531", "exp_l1l2_summary_eps0.1*.json"))):
    merged.update(json.load(open(f)))
name = "exp_l1l2_summary_eps0.1.json"
p = os.path.join(M, name)
json.dump(merged, open(p, "w"), indent=1)
print("  %-34s %4d basins, %.2f MB" % (name, len(merged), os.path.getsize(p) / 1e6))
print("  npz records kept on HPC: %d" % len(glob.glob(os.path.join(R, "l1l2_531", "l1l2_records", "*.npz"))))

print("=== SANITY: every block must hold 531 unique basins ===")
for f in sorted(glob.glob(os.path.join(M, "*.json"))):
    d = json.load(open(f))
    n = len(d)
    print("  %-34s %4d %s" % (os.path.basename(f), n, "OK" if n == 531 else "<-- CHECK"))
PY

echo "=== HAND BACK THROUGH OUTBOX ==="
mkdir -p $OUTBOX
cp -f /data1/home/$USER/adv531/results/05_adversarial_robustness/id18_s100_merged/*.json $OUTBOX/
cd $OUTBOX && md5sum *.json | sed 's/^/  /'
echo "  total: $(du -sh $OUTBOX | cut -f1)"
