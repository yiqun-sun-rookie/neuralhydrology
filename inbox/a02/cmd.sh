#!/bin/bash
# a02 seq=1 : read-only preflight for experiment A02 (nature_1st seed ensemble)
export LC_ALL=C

echo "=== A LANDING SITE (must not exist yet) ==="
ls -d ~/nature_1st_a02 2>&1 || echo "  clean: ~/nature_1st_a02 does not exist"
ls -la ~/ | grep -iE "nature|a02|\.tar\.gz" 2>&1 | head -10 || echo "  no matching entries"

echo "=== B DISK ==="
df -h /data1 2>&1 | tail -2
du -sh ~/hpc_mailbox 2>&1

echo "=== C ENV nh_final (pyarrow still missing?) ==="
NHP=/data1/home/$USER/miniconda3/envs/nh_final/bin/python
$NHP -c "
import importlib
for m in ['torch','pandas','numpy','pyarrow','tqdm']:
    try:
        mod=importlib.import_module(m)
        print('  OK  ',m,getattr(mod,'__version__','?'))
    except Exception as e:
        print('  MISS',m,type(e).__name__)
" 2>&1 | head -8

echo "=== D PIP CHANNEL REACHABLE (no install, dry check) ==="
timeout 60 /data1/home/$USER/miniconda3/envs/nh_final/bin/pip index versions pyarrow 2>&1 | head -4 || echo "  pip index unsupported or slow; will fall back to plain install"

echo "=== E GPU PARTITION NOW ==="
sinfo -p hgpu2p -o "%12P %8a %6D %24N %8t" 2>&1 | head -8
echo "--- my running/pending jobs (all lines, to check contention) ---"
squeue -u "$USER" -o "%.10i %.16j %.9P %.8T %.10M %.20R" 2>&1 | head -12

echo "=== F MAILBOX OUTBOX STATE ==="
ls -la ~/hpc_mailbox/outbox/ 2>&1 | head -12
