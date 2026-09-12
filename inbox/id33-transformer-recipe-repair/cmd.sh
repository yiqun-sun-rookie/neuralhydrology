#!/bin/bash
# seq=55 scheduled watch: pull seed-wave epoch-30 per-basin NSE (basin,nse) for local archiving; read-only
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
cd "$ROOT" || exit 1
date -Iseconds
echo "=== SACCT ==="
sacct -j 225187,225190,225191,225192,225199,225200,225201 -X -o JobID,JobName%14,State,ExitCode,Elapsed,NodeList -P 2>&1 || true
echo "=== MANIFEST HASH CHECK ==="
for m in results/33_transformer_recipe_repair/_invocations/*_s[2-8]00_slurm*/run_manifest.json; do
  python3 - "$m" <<'PY' 2>&1 || true
import json,sys
m=json.load(open(sys.argv[1]))
def find(o,keys):
    out={}
    def rec(o,p):
        if isinstance(o,dict):
            for k,v in o.items():
                if any(x in k.lower() for x in keys) and isinstance(v,(str,int)): out[p+'/'+k]=v
                rec(v,p+'/'+k)
        elif isinstance(o,list):
            for i,v in enumerate(o): rec(v,p+f'[{i}]')
    rec(o,''); return out
print(sys.argv[1].split('/')[-2], 'status=',m.get('status'), 'rc=',m.get('training_return_code'), 'data_access=',(m.get('data_access') or {}).get('status'))
h=find(m,['sha','hash','digest'])
vals=[v for k,v in h.items() if 'source' in k.lower() or 'code' in k.lower() or 'src' in k.lower()]
print('  source-ish hashes distinct:',len(set(vals)),'of',len(vals))
PY
done
echo "=== UTILISATION ==="
for f in logs/33_transformer_recipe_repair/utilisation-2251*.csv; do
  echo "-- $f"; python3 -c "
import csv,sys
r=list(csv.DictReader(open('$f')))
cols=list(r[0].keys()) if r else []
print('rows',len(r),'cols',cols)
for c in cols:
    try:
        v=[float(x[c]) for x in r if x[c] not in ('','nan')]
        if v: print(' ',c,'mean=%.1f max=%.1f'%(sum(v)/len(v),max(v)))
    except Exception: pass
" 2>&1 || true
done
echo "=== PER-BASIN EPOCH30 (basin,NSE) ==="
for f in results/33_transformer_recipe_repair/*_s[2-8]00/*/validation/model_epoch030/validation_metrics.csv; do
  arm=$(echo "$f" | cut -d/ -f3)
  echo "##ARM $arm"
  python3 -c "
import csv
r=list(csv.DictReader(open('$f')))
b=[c for c in r[0] if c.lower() in ('basin','basin_id')][0]; k=[c for c in r[0] if c.lower()=='nse'][0]
for x in r: print(x[b]+','+x[k])
" 2>&1 || true
done
echo "=== BEST-EPOCH MEDIANS ==="
for d in results/33_transformer_recipe_repair/*_s[2-8]00/*/; do
  arm=$(echo "$d" | cut -d/ -f3)
  python3 -c "
import csv,statistics,glob
best=None
for f in sorted(glob.glob('$d'+'validation/model_epoch0*/validation_metrics.csv')):
    r=list(csv.DictReader(open(f))); k=[c for c in r[0] if c.lower()=='nse'][0]
    v=[float(x[k]) for x in r if x[k] not in ('','nan')]; m=statistics.median(v); ep=f.split('model_epoch')[1][:3]
    if best is None or m>best[1]: best=(ep,m)
print('$arm','best_epoch',best[0],'best_median %.6f'%best[1])
" 2>&1 || true
done
