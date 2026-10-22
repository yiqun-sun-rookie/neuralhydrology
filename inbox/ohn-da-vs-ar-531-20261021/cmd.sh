#!/bin/bash
# Own jobs have been Priority-pending ~2 h with nothing running. Widen partitions of OWN pending jobs without changing
# card type for DA arms: hgpu2 has the same RTX 3090 as hgpu2p. A1 training (card type irrelevant) may also use hgpu4 (A40).
# ngu002 stays excluded. Nothing else touched.
set -o pipefail
date --iso-8601=seconds
echo "=== FREE GPUS ==="
for P in hgpu2p hgpu2 hgpu4 hgpu8; do
  FREE=$(sinfo -p $P -N -h -O statecompact:10,gres:14,gresused:24 2>/dev/null | awk '
      $1 ~ /^(idle|mix)$/ { t=$2; u=$3; sub(/^gpu:/,"",t); sub(/\(.*/,"",t); sub(/,.*/,"",t);
                            sub(/^gpu:/,"",u); sub(/\(.*/,"",u); sub(/,.*/,"",u); f+=t-u }
      END { print f+0 }')
  echo "$P free_gpus=$FREE"
done
echo "=== WIDEN PARTITIONS (pending only) ==="
upd() {  # upd <jobid> <partitions>
  local st; st=$(squeue -j "$1" -h -o '%T' 2>/dev/null | sort -u | tr '\n' ' ')
  echo "job $1 states: ${st:-GONE}"
  case "$st" in *PENDING*) scontrol update jobid="$1" Partition="$2" 2>&1 && echo "  -> Partition=$2" ;; esac
}
upd 246243 hgpu2p,hgpu2
upd 246378 hgpu2p,hgpu2
upd 246280 hgpu2p,hgpu2
upd 246279 hgpu2p,hgpu2,hgpu4
echo "=== AFTER ==="
squeue -j 246243,246378,246279,246280,246281 -h -o '%i|%P|%T|%R|%S' 2>&1 | head -12
for J in 246243 246279; do scontrol show job $J 2>/dev/null | grep -oE 'ExcNodeList=[^ ]*' | sort -u | head -1; done
echo "SEQ23_DONE"
