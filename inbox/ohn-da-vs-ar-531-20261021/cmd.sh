#!/bin/bash
# OHN DA-vs-AR seq3: hgpu8 nodes ngu201/202 are ReqNodeNotAvail -> move OWN pending smoke jobs 246200/246201 to the
# GPU partition with most free cards (not hgpu8); deploy code/config v2 into OWN root (old code backed up, not deleted).
set -o pipefail
CH=ohn-da-vs-ar-531-20261021
NEW=/data1/home/sunyiq/ohn_da_vs_ar_531_20261021
PAY=$HOME/hpc_mailbox/inbox/$CH/payload/payload_v2.tar.gz
EXP_SHA=4c326aa3d5dd3983d4e285861198683868396013d8f1e1256baa014249d45abb
date --iso-8601=seconds

echo "=== HGPU8 NODE STATE (read-only) ==="
sinfo -p hgpu8 -N -h -o '%N|%T|%E|%H' 2>&1
scontrol show node ngu201 2>&1 | grep -E 'State=|Reason=' | head -3
echo "=== FREE GPUS (excluding hgpu8) ==="
BEST=hgpu2p; BEST_FREE=-1
for P in hgpu4 hgpu2p hgpu2; do
  FREE=$(sinfo -p $P -N -h -O statecompact:10,gres:14,gresused:24 2>/dev/null | awk '
      $1 ~ /^(idle|mix)$/ { t=$2; u=$3; sub(/^gpu:/,"",t); sub(/\(.*/,"",t); sub(/,.*/,"",t);
                            sub(/^gpu:/,"",u); sub(/\(.*/,"",u); sub(/,.*/,"",u); f+=t-u }
      END { print f+0 }')
  echo "$P free_gpus=$FREE"
  if [ "$FREE" -gt "$BEST_FREE" ]; then BEST=$P; BEST_FREE=$FREE; fi
done
[ "$BEST_FREE" -gt 0 ] || BEST=hgpu2p
echo "CHOSEN_PARTITION=$BEST"

echo "=== MOVE OWN PENDING SMOKES ==="
for J in 246200 246201; do
  ST=$(squeue -j $J -h -o '%T' 2>/dev/null)
  echo "job $J state=${ST:-GONE}"
  [ "$ST" = "PENDING" ] || continue
  scontrol update jobid=$J partition=$BEST 2>&1
  squeue -j $J -h -o '%i %P %T %R' 2>&1
done
echo "$BEST" > "$NEW/logs/partition_p1.txt"

echo "=== DEPLOY V2 (own root; backup old code) ==="
[ -f "$PAY" ] || { echo PAYLOAD_MISSING; exit 1; }
GOT=$(sha256sum "$PAY" | cut -d' ' -f1); [ "$GOT" = "$EXP_SHA" ] || { echo "PAYLOAD_SHA_MISMATCH $GOT"; exit 1; }
[ -e "$NEW/code_v1" ] && { echo "CODE_V1_BACKUP_EXISTS (v2 already deployed?)"; ls "$NEW"; exit 0; }
STG="$NEW/stage_v2"
[ -e "$STG" ] && { echo "STAGE_EXISTS"; exit 1; }
tar -xzf "$PAY" -C "$NEW" 2>&1 | grep -v 'implausibly old' || true
(cd "$STG" && sha256sum -c MANIFEST_v2.sha256 > ../logs/manifest_v2.txt 2>&1) || { echo MANIFEST_V2_FAILED; cat "$NEW/logs/manifest_v2.txt"; exit 1; }
echo "manifest v2 OK $(grep -c ': OK$' "$NEW/logs/manifest_v2.txt") files"
cp -a "$NEW/code" "$NEW/code_v1"
cp "$STG"/code/*.py "$NEW/code/"
mkdir -p "$NEW/configs/grid"
cp -n "$STG"/configs/grid/* "$NEW/configs/grid/"
cp -n "$STG"/slurm/*.slurm "$NEW/slurm/"
ls "$NEW/code" "$NEW/configs/grid" | tr '\n' ' '; echo
diff -q "$NEW/code_v1/safe_da.py" "$NEW/code/safe_da.py" || true
echo "SEQ3_DONE"
