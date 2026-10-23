#!/bin/bash
# READ_ONLY_VALIDATE_RESULT: summarize validate stage result of 241337; no mutation
S=/data1/home/sunyiq/hydrol85935_revision_20261008_001/control/hybrid_v009_20261012_001
ls -la $S/stage_results/ | grep validate
tail -c 600 $S/logs/validate-241337_4294967294.err 2>/dev/null; ls $S/logs | grep 241337
F=$(ls $S/stage_results/validate_0_241337.json 2>/dev/null) || { echo VR_MISSING; exit 3; }
sha256sum $F
python3 - "$F" <<'PY'
import json,sys,re,collections
r=json.load(open(sys.argv[1]))
print('VR_KEYS',sorted(r))
print('VR_STATUS',r.get('status'),r.get('exit_code'),round(r.get('wall_seconds',0)),'traceback' in r)
print('VR_COUNTS',json.dumps(r.get('counts')));print('VR_EXPECTED',json.dumps(r.get('expected')))
f=r.get('failures',[]);print('VR_FAILURES',len(f),'unexpected',len(r.get('unexpected',[])))
c=collections.Counter((x['kind'],re.sub(r'[0-9.e+-]{4,}','#',x['error'])[:150]) for x in f)
for k,n in c.most_common(20):print('VR_CLASS',n,k)
print('VR_BASINS',len({x.get('basin') for x in f}),'COMBOS',len({x.get('combination') for x in f}))
if 'traceback' in r:print(r['traceback'][-1500:])
PY
exit 0
