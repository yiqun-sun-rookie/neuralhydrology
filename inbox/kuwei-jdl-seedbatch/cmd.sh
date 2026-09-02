#!/bin/bash
# Read-only: stage-1 2023 verdict.
set -o pipefail
ROOT=$HOME/kuwei_jdl_seedbatch_20260831
RES=$ROOT/laos/basins/namou_kuwei/dl/highflow_2026_06_17/results/kuwei_joint_da_learning_20260826
echo "=== A. sacct 218673 ==="
sacct -j 218673 -X --format=JobID%14,State%16,ExitCode%8,Elapsed%10 --noheader 2>&1 | head -4 || true
echo "=== B. stdout ==="
tail -32 $ROOT/logs/kuwei-jdl-eval-218673.out 2>&1 || true
echo "=== C. stderr ==="
tail -8 $ROOT/logs/kuwei-jdl-eval-218673.err 2>&1 || true
echo "=== D. verdict json (full) ==="
cat $RES/seedbatch_stage1_2023.json 2>&1 | python -c "
import json,sys
try:
    d=json.load(sys.stdin)
except Exception as e:
    print('not ready:',e); raise SystemExit
print('VERDICT:', d['verdict'])
print('hydro_only spread (registered readout):', d['registered_primary_readout_hydro_only_spread'])
print()
for arm,s in d['summary'].items():
    rs=s['ratios_by_learning_seed']
    print('%-11s' % arm, '  '.join('ls%s=%.5f'%(k,v) for k,v in sorted(rs.items())))
    print('           spread=%.5f median=%.5f min=%.5f max=%.5f'%(s['spread_max_minus_min'],s['median'],s['min'],s['max']))
print()
print('baseline all_frozen combined_mse =', d['baseline_all_frozen_combined_mse'])
print('env =', d['environment'])
print()
print('nse24 per run:')
for k,v in sorted(d['results'].items()):
    print('   %-22s mse=%9.4f  nse24=%.4f' % (k, v['combined_mse'], v['per_lead']['24']['nse']))
" 2>&1 || true
echo "=== E. sha256 ==="
sha256sum $RES/seedbatch_stage1_2023.json 2>&1 || true
echo "=== DONE ==="
