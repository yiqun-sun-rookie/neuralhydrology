#!/bin/bash
# Dispatch only after independent review of all development evidence and this script.
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
import datetime,hashlib,json,math,pathlib,re,subprocess

ROOT=pathlib.Path('/data1/home/sunyiq/id29_xinanjiang_transfer_20260907_v01')
EXPECTED={
 'bundle/MANIFEST.json':'59a8f8b50776086c5b1263e441cfc9cf80299b80feca24a60919d582d5d21545',
 'development/summary.json':'9b7266cd32fd1a7278002257d483a8b5cb70be2c744985516f1b343cccd1bfec',
 'development/frozen_transfer.json':'5f644f707c9b67eacf89562e7484cfc42f859dfcdad597b1eeb58584a99a2d04',
 'development/learned.json':'7ee957c486a89f8b0106010bdf310539c147de672f93fdd3fa38c76ec1087bf4',
 'development/evaluation_records.json':'2abf58515620b1510b595e9ec031d79d40305b06663a02502bf7858873ab2adb',
 'development/execution.json':'6e4588bc1851de7c678f2360e0b45540336d93650557e66205d487329d644de9',
 'pilot/summary.json':'f5f124944f652809dd33fbc9c0fbb9dac44bd30c3ec146cd760e1d138aa70640',
}

def read(path):
    return json.loads(path.read_text())

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def require(condition,message):
    if not condition: raise ValueError(message)

def validate(root):
    for name in ['receiver','receiver_job_id.txt','approve_receiver.json','receiver_submission_receipt.json']:
        require(not (root/name).exists(),'receiver stage/submission already exists: '+name)
    for name,expected in EXPECTED.items():
        require(digest(root/name)==expected,'audited prerequisite changed: '+name)
    for name,expected in read(root/'bundle/MANIFEST.json').items():
        require(digest(root/'bundle'/name)==expected,'frozen bundle member changed: '+name)
    for name,expected in read(root/'bundle/inputs/manifest.json').items():
        require(digest(root/'bundle/inputs'/name)==expected,'frozen input changed: '+name)
    dev=read(root/'bundle/inputs/development_basins.json')
    rec=read(root/'bundle/inputs/receiver_basins.json')
    require(len(dev)==len(set(dev))==49 and len(rec)==len(set(rec))==360 and not set(dev)&set(rec),'basin identity/count')
    summary=read(root/'development/summary.json')
    require(summary['status']=='success' and summary['candidate_evaluations']==37632
            and 0<=summary['failed_candidates']<=37632*.01 and summary['successful_arm_basins']==1176
            and summary['transfer_sha256']==EXPECTED['development/frozen_transfer.json'],'development success/count gate')
    frozen=read(root/'development/frozen_transfer.json')
    require(frozen['donors']==dev and frozen['baseline']=='uniform_2'
            and frozen['bundle_manifest_sha256']==EXPECTED['bundle/MANIFEST.json'],'frozen transfer identity')
    for key in ['ratio','absolute_std']:
        require(len(frozen[key])==8 and all(math.isfinite(v) and v>0 for v in frozen[key]),'invalid transfer vector')
    learned=read(root/'development/learned.json')
    require(set(learned)==set(dev) and all(v['status']=='success' and v['evaluations']==768
            and len(v['endpoints'])==8 for v in learned.values()),'learning completeness')
    records=read(root/'development/evaluation_records.json')
    arms=({f'uniform_{i}' for i in range(5)}|{f'fixed_anchor_{i}' for i in range(8)}
          |{f'learned_anchor_{i}' for i in range(8)}|{'pooled_ratio','pooled_absolute','open_loop'})
    require(len(records)==49 and {r['basin_id'] for r in records}==set(dev)
            and all(r['status']=='success' and len(r['arms'])==24 and {a['arm'] for a in r['arms']}==arms
                    and all(a['status']=='success' and math.isfinite(a['nse']) for a in r['arms']) for r in records),
            '1176 complete successful development evaluations required')
    execution=read(root/'development/execution.json')
    require(execution['job_id']=='223708' and execution['workers']==24 and execution['stage']=='development'
            and execution['bundle_manifest_sha256']==EXPECTED['bundle/MANIFEST.json'],'development execution identity')
    require((root/'development_job_id.txt').read_text().strip().split(';')[0]=='223708','development job identity')
    pilot=read(root/'pilot/summary.json')
    seconds=pilot['estimated_seconds']['receiver']
    require(pilot['status']=='success' and pilot['resource_gate'] is True
            and math.isfinite(seconds) and 0<seconds<=6*3600,'receiver resource estimate gate')
    script=(root/'bundle/src/xinanjiang_transfer_noise/hpc/receiver.slurm').read_text()
    require('#SBATCH --cpus-per-task=24' in script.splitlines() and '#SBATCH --time=08:00:00' in script.splitlines()
            and not any(x in script for x in ['#SBATCH --mem','#SBATCH --gres','#SBATCH --gpus']), 'receiver resource authority')
    status=subprocess.run(['sacct','-j','223708','-n','-P','--format=JobIDRaw,State,ExitCode'],
                          check=True,capture_output=True,text=True,timeout=40).stdout.splitlines()
    require(any(row.split('|')[:3]==['223708','COMPLETED','0:0'] for row in status),'development Slurm terminal state')

def write_exclusive(path,value):
    with path.open('x') as stream:
        json.dump(value,stream,sort_keys=True,indent=2,allow_nan=False)
        stream.write('\n')

def release(root):
    validate(root)
    approval={'approved':True,'scope':'receiver_only_360_basins_2880_arms',
              'reviewer':'second_model_independent_review','maximum_cpus':24,'maximum_hours':8,
              'prerequisite_sha256':EXPECTED['development/summary.json'],
              'transfer_sha256':EXPECTED['development/frozen_transfer.json'],
              'bundle_manifest_sha256':EXPECTED['bundle/MANIFEST.json'],
              'audited_prerequisites':EXPECTED,'development_job':'223708',
              'created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat()}
    # An exclusive approval is also the single-submission lock; retain it on uncertainty/failure.
    write_exclusive(root/'approve_receiver.json',approval)
    try:
        result=subprocess.run(['sbatch','--parsable','src/xinanjiang_transfer_noise/hpc/receiver.slurm'],
                              cwd=root/'bundle',capture_output=True,text=True,timeout=40)
    except Exception as exc:
        write_exclusive(root/'receiver_submission_receipt.json',{'status':'uncertain','error':type(exc).__name__+': '+str(exc)})
        raise RuntimeError('submission uncertain; retain approval and inspect before any action') from exc
    write_exclusive(root/'receiver_submission_receipt.json',
                    {'status':'returned','returncode':result.returncode,'stdout':result.stdout,'stderr':result.stderr})
    require(result.returncode==0,'sbatch returned failure; preserve output, no automatic retry')
    job=result.stdout.strip()
    require(re.fullmatch(r'[0-9]+(?:;[A-Za-z0-9_.-]+)?',job) is not None,
            'submission response ambiguous; inspect job state, do not resubmit')
    with (root/'receiver_job_id.txt').open('x') as stream:
        stream.write(job+'\n')
    print('RECEIVER_GATE_APPROVED',EXPECTED['development/summary.json'])
    print('SUBMITTED_RECEIVER_JOB='+job)
    status=subprocess.run(['squeue','-j',job.split(';')[0],'-o','%.18i %.20j %.10T %.10M %.6D %R'],
                          capture_output=True,text=True,timeout=40)
    print(status.stdout)
    if status.returncode: print('SQUEUE_SNAPSHOT_UNAVAILABLE',status.stderr)

if __name__=='__main__':
    release(ROOT)
PY
