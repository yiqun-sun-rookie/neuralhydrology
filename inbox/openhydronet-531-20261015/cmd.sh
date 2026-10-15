#!/bin/bash
set -o pipefail
# READ-ONLY: diff HPC manifest vs local manifest
ROOT=/data1/home/sunyiq/openhydronet_531_20261015
P="$HOME/hpc_mailbox/inbox/openhydronet-531-20261015/payload/v2"
source ~/miniconda3/etc/profile.d/conda.sh; conda activate nh_final || exit 1
python - "$P/manifest_local.tsv" "$ROOT/manifests/camels_us_hpc.tsv" <<'PY'
import sys
def rd(p): return {l.split('\t')[0]: l.rstrip('\n').split('\t')[1:] for l in open(p) if l.strip()}
a, b = rd(sys.argv[1]), rd(sys.argv[2])
print('local files', len(a), 'hpc files', len(b), 'only local', len(set(a) - set(b)), 'only hpc', len(set(b) - set(a)))
diff = [k for k in a if k in b and a[k][0] != b[k][0]]
print('different content:', len(diff))
for k in diff: print('  ', k, 'local bytes', a[k][1], 'hpc bytes', b[k][1])
PY
for f in $(python - "$P/manifest_local.tsv" "$ROOT/manifests/camels_us_hpc.tsv" <<'PY'
import sys
def rd(p): return {l.split('\t')[0]: l.rstrip('\n').split('\t')[1:] for l in open(p) if l.strip()}
a, b = rd(sys.argv[1]), rd(sys.argv[2])
print(' '.join(k for k in a if k in b and a[k][0] != b[k][0]))
PY
); do echo "--- HPC head of $f"; head -4 "$HOME/neuralhydrology/data/camels_us/$f" | cut -c1-80; done
exit 0
