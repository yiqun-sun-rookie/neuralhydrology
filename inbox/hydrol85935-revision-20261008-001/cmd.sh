#!/bin/bash
# READ_ONLY_VALIDATE_CLASSES: classify failures in validate 241337 stdout; no mutation
O=/data1/home/sunyiq/hydrol85935_revision_20261008_001/control/hybrid_v009_20261012_001/logs/validate-241337_4294967294.out
sha256sum $O
python3 - "$O" <<'PY'
import json,sys,re,collections
r=[json.loads(l) for l in open(sys.argv[1]) if l.startswith('{"stage": "validate"')][-1]
print('VR_STATUS',r.get('status'),r.get('exit_code'),round(r.get('wall_seconds',0)),'traceback' in r,r.get('hpc_subset_complete'))
print('VR_COUNTS',json.dumps(r['counts']));print('VR_EXPECTED',json.dumps(r['expected']))
f=r['failures'];print('VR_FAILURES',len(f),'UNEXPECTED',len(r['unexpected']),r['unexpected'][:5])
def cls(x):
    e=x['error']
    for k in ('Baseline reproduction failed','Required clean reference is missing','not_executed','empty','infeasible','intersection'):
        if k in e:return k
    return re.sub(r'\d','#',e)[:160]
c=collections.Counter((x['kind'],cls(x)) for x in f)
for k,n in c.most_common():print('VR_CLASS',n,k)
st=collections.Counter(re.search(r"'status': '(\w+)'",x['error']).group(1) if "'status':" in x['error'] else '-' for x in f if x['kind']=='attack')
print('VR_ATTACK_LEDGER_STATUS',dict(st))
oth=[x for x in f if cls(x) not in ('Baseline reproduction failed','Required clean reference is missing')]
for x in oth[:15]:print('VR_OTHER',x.get('combination'),x.get('basin'),x['error'][:300])
cl={(x['model'],x['basin']) for x in f if x['kind']=='clean'}
print('VR_CLEAN_FAILED',len(cl),collections.Counter(m for m,b in cl))
ab={(x['combination'].rsplit('_',4)[0] if False else '_'.join(x['combination'].split('_')[:2]),x['basin']) for x in f if x['kind']=='attack'}
print('VR_ATTACK_MODEL_BASIN',len(ab),collections.Counter(m for m,b in ab)); print('VR_ATTACK_NOT_IN_CLEAN',sorted(ab-cl)[:20])
PY
exit 0
