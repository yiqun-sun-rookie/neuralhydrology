#!/bin/bash
# Run only after independent review of the completed technical artifacts.
set -eo pipefail
TASK_ROOT=/data1/home/sunyiq/id29_xinanjiang_transfer_20260907_v01
test ! -e "$TASK_ROOT/development" || { echo 'DEVELOPMENT_ALREADY_EXISTS'; exit 10; }
test ! -e "$TASK_ROOT/development_job_id.txt" || exit 11
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
import hashlib,json,math,pathlib,subprocess,xml.etree.ElementTree as ET
root=pathlib.Path('/data1/home/sunyiq/id29_xinanjiang_transfer_20260907_v01')
expected_summary='f5f124944f652809dd33fbc9c0fbb9dac44bd30c3ec146cd760e1d138aa70640'
expected_manifest='59a8f8b50776086c5b1263e441cfc9cf80299b80feca24a60919d582d5d21545'
digest=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
summary_path=root/'pilot/summary.json'
if digest(summary_path)!=expected_summary or digest(root/'bundle/MANIFEST.json')!=expected_manifest:
    raise ValueError('prerequisite identity mismatch')
summary=json.loads(summary_path.read_text())
if summary['status']!='success' or summary['resource_gate'] is not True:
    raise ValueError('technical or resource gate failed')
for key,bound in [('development',16*3600),('receiver',6*3600)]:
    value=summary['estimated_seconds'][key]
    if not math.isfinite(value) or not 0<value<=bound:
        raise ValueError('resource estimate exceeds authority')
tests=ET.parse(root/'pilot-tests.xml').getroot().find('testsuite').attrib
if tests['tests']!='42' or any(tests[x]!='0' for x in ['errors','failures','skipped']):
    raise ValueError('technical test gate failed')
status=subprocess.run(['sacct','-j','223694','-n','-P','--format=JobIDRaw,State,ExitCode'],
                      check=True,capture_output=True,text=True).stdout.splitlines()
if not any(row.split('|')[:3]==['223694','COMPLETED','0:0'] for row in status):
    raise ValueError('technical Slurm terminal state is not successful')
approval={'approved':True,'scope':'development_only_49_basins',
          'reviewer':'second_model_independent_review',
          'prerequisite_sha256':expected_summary,'bundle_manifest_sha256':expected_manifest,
          'maximum_cpus':24,'maximum_hours':24,'technical_job':'223694'}
with (root/'approve_development.json').open('x') as stream:
    json.dump(approval,stream,sort_keys=True,indent=2)
print('DEVELOPMENT_GATE_APPROVED',expected_summary)
PY
cd "$TASK_ROOT/bundle"
SUBMITTED_JOB=$(sbatch --parsable src/xinanjiang_transfer_noise/hpc/development.slurm)
printf '%s\n' "$SUBMITTED_JOB" > "$TASK_ROOT/development_job_id.txt"
printf 'SUBMITTED_DEVELOPMENT_JOB=%s\n' "$SUBMITTED_JOB"
squeue -j "${SUBMITTED_JOB%%;*}" -o '%.18i %.12j %.10T %.10M %.6D %R'
