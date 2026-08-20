#!/bin/bash
# nature1st-attr-swap -- install and SUBMIT arms E and F (user authorised 2026-08-20).
#   arm E  4 attributes  = the winning 8 minus the 4 the global set cannot reconstruct
#   arm F  17 attributes = the 13 global plus those same 4  (same count as arm D)
# The submit is gated on a byte-level fingerprint check: mismatch => abort, no job.
# This cmd.sh MUST be superseded by a status-only one right after it runs -- a daemon
# restart re-scans the channel and a leftover submit command would duplicate the jobs.
set -o pipefail
CH=nature1st-attr-swap
IN=$HOME/hpc_mailbox/inbox/$CH
RUN=/data1/home/sunyiq/nature_1st

echo "=== A. INSTALL ==="
for f in chain_prepare_attrset.py chain_train_q_attrset.py chain_eval_q_attrset.py \
         hpc_train_q_armE_minus4.sbatch hpc_train_q_armF_plus4.sbatch; do
    cp -v "$IN/$f" "$RUN/scripts/" 2>&1
done
cp -v "$IN/stage_static_feature_stats_armE.json" "$RUN/data/interim/" 2>&1
cp -v "$IN/stage_static_feature_stats_armF.json" "$RUN/data/interim/" 2>&1
cp -v "$IN/trainable_mountain_stations_armF.csv" "$RUN/data/processed/station_meta/" 2>&1
sed -i 's/\r$//' "$RUN"/scripts/chain_*_attrset.py "$RUN"/scripts/hpc_train_q_arm[EF]_*.sbatch \
                 "$RUN"/data/interim/stage_static_feature_stats_arm[EF].json \
                 "$RUN"/data/processed/station_meta/trainable_mountain_stations_armF.csv 2>&1

echo "=== B. FINGERPRINT GATE (submit only if all three match) ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || \
source $HOME/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate "${CONDA_ENV:-nh_final}" 2>&1 | head -2
python - <<'PY' 2>&1
import hashlib, json, sys
import pandas as pd
from pathlib import Path
R = Path("/data1/home/sunyiq/nature_1st")
WANT = {"statsE": ("8ae820476141bd2a", 4), "statsF": ("1398b7375f651487", 17),
        "metaF": ("be45af293fad3c92", (2908, 18))}
ok = True
for tag, p in [("statsE", R / "data/interim/stage_static_feature_stats_armE.json"),
               ("statsF", R / "data/interim/stage_static_feature_stats_armF.json")]:
    d = json.loads(p.read_text())
    h = hashlib.sha256(json.dumps(d, sort_keys=True).encode()).hexdigest()[:16]
    good = (h, len(d)) == WANT[tag]
    ok &= good
    print(f"{tag} {h} n={len(d)} {'MATCH' if good else 'MISMATCH want ' + str(WANT[tag])}")
df = pd.read_csv(R / "data/processed/station_meta/trainable_mountain_stations_armF.csv")
h = hashlib.sha256(df.to_csv(index=False, lineterminator="\n").encode()).hexdigest()[:16]
good = (h, df.shape) == WANT["metaF"]
ok &= good
print(f"metaF  {h} shape={df.shape} {'MATCH' if good else 'MISMATCH want ' + str(WANT['metaF'])}")
print("GATE_" + ("PASS" if ok else "FAIL"))
sys.exit(0 if ok else 1)
PY
GATE=$?
[ "$GATE" -eq 0 ] || { echo "ABORT: fingerprint gate failed, nothing submitted"; exit 1; }

echo "=== C. OUTPUT DIRS MUST BE ABSENT ==="
BLOCK=0
for d in q_lstm_armE_hpc_s42 q_lstm_armF_hpc_s42; do
    if [ -e "$RUN/models/$d" ]; then echo "PRESENT $d -- refusing to submit"; BLOCK=1; \
    else echo "absent  $d (good)"; fi
done
[ "$BLOCK" -eq 0 ] || { echo "ABORT: stale output dir(s)"; exit 1; }

echo "=== D. SUBMIT ==="
cd "$RUN" || exit 1
mkdir -p logs/attr_swap
JIDS=""
for s in armE_minus4 armF_plus4; do
    out=$(sbatch scripts/hpc_train_q_${s}.sbatch 2>&1)
    line=$(echo "$out" | grep -E 'Submitted batch job [0-9]+' || echo "NO JOB ID -- rejected")
    echo "[$s] $line"
    jid=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+$' || true)
    if [ -z "$jid" ]; then echo "[$s] SUBMIT_FAILED, wrapper said:"; echo "$out" | head -20; \
    else JIDS="$JIDS $jid"; fi
done
echo "jids=$JIDS"

echo "=== E. WAIT 4 min, verify node + GPU + attribute guards ==="
sleep 240
for j in $JIDS; do
    sacct -j "$j" -X --format=JobID%10,JobName%24,State%12,ExitCode%8,Elapsed%10,NodeList%9 2>&1 | tail -2
done
for f in $(ls -t "$RUN"/logs/attr_swap/armE_minus4-*.out "$RUN"/logs/attr_swap/armF_plus4-*.out 2>/dev/null | head -2); do
    echo "--- $f ---"; head -10 "$f" 2>&1
done
echo "-- guard lines (want 4 attributes / 17 attributes) --"
grep -h '\[guard\]' "$RUN"/logs/attr_swap/armE_minus4-*.out "$RUN"/logs/attr_swap/armF_plus4-*.out 2>/dev/null | head -6 || true
echo "-- any FATAL / traceback? --"
grep -l 'FATAL\|Traceback' "$RUN"/logs/attr_swap/armE_minus4-*.err "$RUN"/logs/attr_swap/armF_plus4-*.err 2>/dev/null || echo "none"

echo "=== END submit round ==="
