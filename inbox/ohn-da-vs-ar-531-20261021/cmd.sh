#!/bin/bash
# Read-only: can the job env (nh_final + OLD/pysite) run on CentOS 7 nodes (hgpu2 ngu003/009, hgpu4)? Inspect wheel tags
# and the highest GLIBC symbol needed by compiled .so files in pysite. Plus queue position of own jobs.
set -o pipefail
OLD=/data1/home/sunyiq/openhydronet_531_20261015
date --iso-8601=seconds
echo "=== PYSITE WHEEL TAGS (non-pure) ==="
grep -h '^Tag:' $OLD/pysite/*.dist-info/WHEEL 2>/dev/null | grep -v 'none-any' | sort | uniq -c | sort -rn | head -20
echo "=== PYSITE manylinux_2_2x/2_3x tagged dists ==="
grep -l -E '^Tag:.*manylinux_2_(2[89]|3[0-9])' $OLD/pysite/*.dist-info/WHEEL 2>/dev/null | xargs -r -n1 dirname | xargs -r -n1 basename | head -20
echo "=== MAX GLIBC SYMBOL PER .so (top 10) ==="
find $OLD/pysite -name '*.so*' -type f 2>/dev/null | head -400 | while read f; do
  v=$(strings -a "$f" 2>/dev/null | grep -oE '^GLIBC_2\.[0-9]+' | sort -t. -k2,2n -u | tail -1)
  [ -n "$v" ] && echo "$v $f"
done | sort -t. -k2,2n | tail -10 | sed "s#$OLD/##"
echo "=== nh_final torch build ==="
ls ~/miniconda3/envs/nh_final/lib/python3.11/site-packages | grep -iE '^torch-|^numpy-|^xarray-|^zarr-' | head
echo "=== SPRIO own pending ==="
sprio -j 246243,246378,246279 2>&1 | head -8
echo "=== QUEUE DEPTH hgpu2p/hgpu2/hgpu4 (pending GPU jobs, all users) ==="
for P in hgpu2p hgpu2 hgpu4; do echo "$P pending=$(squeue -p $P -h -t PD 2>/dev/null | wc -l) running=$(squeue -p $P -h -t R 2>/dev/null | wc -l)"; done
echo "=== NODE STATE hgpu2p/hgpu2/hgpu4 ==="
for P in hgpu2p hgpu2 hgpu4; do sinfo -p $P -N -h -O nodelist:10,statecompact:8,gres:14,gresused:24 2>/dev/null; done
echo "SEQ24_DONE"
