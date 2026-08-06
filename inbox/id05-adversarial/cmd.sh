#!/bin/bash
# id05-adversarial  aggregate the three finished blocks (read-only, light login-node work)
export LC_ALL=C
P=/data1/home/$USER/miniconda3/envs/nh_final/bin/python

$P - <<'PY'
import json, glob, statistics as st, os
R = os.path.expanduser("~/adv531/results/05_adversarial_robustness/id18_s100_hpc")

def load(pat):
    recs, per_chunk = [], {}
    for f in sorted(glob.glob(os.path.join(R, pat))):
        d = json.load(open(f))
        per_chunk[os.path.basename(f)[-10:]] = len(d)
        recs += d
    return recs, per_chunk

def med(rs, k):
    v = [r[k] for r in rs if k in r and r[k] == r[k]]
    return st.median(v) if v else float("nan")

def chunk0(name):
    fs = glob.glob(os.path.join(R, name))
    return [r for r in json.load(open(fs[0]))] if fs else []

for tag, pat in (("EXP3 flow-targeted", "exp3_531_chunk*.json"),
                 ("EXP6 KGE", "exp6_531_chunk*.json")):
    print(f"############ {tag} ############")
    rs, ch = load(pat)
    ok = [r for r in rs if "error" not in r]
    print(f"  records={len(rs)} ok={len(ok)} errors={len(rs)-len(ok)} chunks={ch}")
    if not ok:
        print("  (nothing yet)"); print(); continue
    keys = [k for k in sorted(ok[0]) if k != "basin"]
    for k in keys:
        print(f"  531    median {k:24s} = {med(ok,k):+.4f}")
    z = [r for r in chunk0(pat.replace('*','0')) if "error" not in r]
    print(f"  --- chunk0 = the published 107 subset (n={len(z)}) ---")
    for k in keys:
        print(f"  c0     median {k:24s} = {med(z,k):+.4f}")
    print()

print("############ L1L2 leave-one-variable-out ############")
merged = {}
for f in sorted(glob.glob(os.path.join(R, "l1l2_531", "exp_l1l2_summary_eps0.1*.json"))):
    d = json.load(open(f))
    merged.update(d)
    print(f"  {os.path.basename(f)}: {len(d)}")
print(f"  merged basins = {len(merged)}")
if merged:
    vals = list(merged.values())
    for k in ("D_nse", "nse_clean", "precip_att", "temp_att", "srad_att", "vp_att"):
        v = [x[k] for x in vals if k in x]
        if v:
            print(f"  531    median {k:12s} = {st.median(v):+.4f}")
    sh = [(x["temp_att"], x["precip_att"], x["temp_att"]+x["precip_att"]+x["srad_att"]+x["vp_att"])
          for x in vals if (x["temp_att"]+x["precip_att"]+x["srad_att"]+x["vp_att"]) > 0]
    print(f"  531    median temp_share   = {st.median([t/z for t,p,z in sh]):.4f}")
    print(f"  531    median precip_share = {st.median([p/z for t,p,z in sh]):.4f}")
    print(f"  npz records on disk = {len(glob.glob(os.path.join(R,'l1l2_531','l1l2_records','*.npz')))}")
PY

echo
echo "=== STILL RUNNING ==="
squeue -u $USER -h -o "%.14i %.16j %.3t %.10M" 2>&1 | head -20
echo "running=$(squeue -u $USER -h -r -t R 2>/dev/null | wc -l) pending=$(squeue -u $USER -h -r -t PD 2>/dev/null | wc -l)"
