#!/bin/bash
# Read-only: state of evaluation job 218673 and the stage-1 verdict json if written.
set -o pipefail
ROOT=$HOME/kuwei_jdl_seedbatch_20260831
RES=$ROOT/laos/basins/namou_kuwei/dl/highflow_2026_06_17/results/kuwei_joint_da_learning_20260826
echo "=== A. sacct 218673 ==="
sacct -j 218673 -X --format=JobID%14,State%16,ExitCode%8,Elapsed%10 --noheader 2>&1 | head -4 || true
echo "=== B. stdout ==="
tail -30 $ROOT/logs/kuwei-jdl-eval-218673.out 2>&1 || true
echo "=== C. stderr ==="
tail -10 $ROOT/logs/kuwei-jdl-eval-218673.err 2>&1 || true
echo "=== D. verdict json ==="
python -c "
import json
p='$RES/seedbatch_stage1_2023.json'
d=json.load(open(p))
print('verdict:', d['verdict'])
print('registered primary readout (hydro_only spread):', d['registered_primary_readout_hydro_only_spread'])
print()
for arm,s in d['summary'].items():
    rs=s['ratios_by_learning_seed']
    print('%-11s ' % arm + '  '.join('ls%s=%.5f'%(k,v) for k,v in sorted(rs.items())))
    print('            spread=%.5f  median=%.5f  min=%.5f  max=%.5f' % (s['spread_max_minus_min'],s['median'],s['min'],s['max']))
print()
print('baseline all_frozen combined_mse =', d['baseline_all_frozen_combined_mse'])
print('env =', d['environment'])
" 2>&1 || true
echo "=== DONE ==="
