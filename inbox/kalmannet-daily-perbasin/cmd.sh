#!/usr/bin/env bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1 PYTHONOPTIMIZE=0
echo 'channel=kalmannet-daily-perbasin sequence=41 purpose=authorized-first-basin-v2-training-on-ngu203-once'
date --iso-8601=seconds
hostname
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B -u - <<'PY_SUBMISSION'
import hashlib, json, os, pathlib, re, subprocess, sys, time
root = pathlib.Path('/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901')
source = root / 'deployments/DAILY_CAMELS_KNET_PER_BASIN_V2_BUNDLE_DEPLOY1_SEQ34/source'
sequence = 41
sha = lambda b: hashlib.sha256(b).hexdigest()
def require(value, message):
    if not value: raise RuntimeError(message)
def run(args, **kwargs):
    kwargs.setdefault('timeout', 45)
    return subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)
def emit(label, result):
    print(label, 'exit_code=' + str(result.returncode), flush=True)
    print(result.stdout.decode('utf-8'), end='', flush=True)
    print(result.stderr.decode('utf-8'), end='', file=sys.stderr, flush=True)
require(root.is_dir() and root.resolve() == root and not root.is_symlink(), 'registered root differs')
require(source.is_dir() and source.resolve() == source and not source.is_symlink(), 'source root differs')
def verify_source():
    archive = source.parent / 'daily_camels_knet_per_basin_pilots_v2.tar.gz'
    require(archive.is_file() and not archive.is_symlink(), 'archive missing or linked')
    data = archive.read_bytes()
    require(len(data) == 438532 and sha(data) == '1b78bbae823d55859391a6cdee3b9fbe8a40203e5140b8795105a8617592b7fd', 'archive mismatch')
    mb = (source / 'bundle_manifest.json').read_bytes()
    require(sha(mb) == '5abaa07cfc00e2795a91a8cd70bb793e5cf362971fd04a2de44cbf3e15fa587f', 'manifest mismatch')
    manifest = json.loads(mb)
    actual = {}
    for path in source.rglob('*'):
        require(not path.is_symlink(), 'source contains link')
        if path.is_file(): actual[path.relative_to(source).as_posix()] = path
        else: require(path.is_dir(), 'source contains special member')
    require(len(actual) == 51 and set(actual) == set(manifest['member_sha256']) | {'bundle_manifest.json'}, 'source members differ')
    require(manifest['member_count'] == 50 and manifest['formal_evaluation_member_count'] == manifest['historical_evaluation_member_count'] == 0, 'member policy mismatch')
    for name, expected in manifest['member_sha256'].items():
        content = actual[name].read_bytes()
        require(sha(content) == expected and len(content) == manifest['member_size_bytes'][name], 'payload mismatch: ' + name)
    print('DEPLOYED_51_FILE_HASH_CHECK=PASS', flush=True)
verify_source()

os.umask(0o077)
queue = run(['squeue','-h','-u',str(os.getuid()),'-o','%i|%200j|%T|%N'])
emit('CURRENT_USER_QUEUE',queue)
require(queue.returncode==0,'queue query failed')
related=[line for line in queue.stdout.decode().splitlines() if re.search(r'kdpp|DAILY_CAMELS_KNET_PER_BASIN|daily.camels.*per.basin|kalmannet.daily.perbasin',line,re.I)]
require(not related,'related active job exists; do not submit')
node=run(['scontrol','show','node','ngu203'])
emit('EXACT_TARGET_NODE',node)
require(node.returncode==0,'node query failed')
node_fields=dict(item.split('=',1) for item in node.stdout.decode().split() if '=' in item)
require(node_fields.get('NodeName')=='ngu203' and node_fields.get('State')=='IDLE' and node_fields.get('CPUAlloc')=='0' and node_fields.get('Partitions')=='hgpu8','target must still be idle and in hgpu8 only')
partition=run(['scontrol','show','partition','hgpu8'])
emit('EXACT_PARTITION',partition)
require(partition.returncode==0,'partition query failed')
pf=dict(item.split('=',1) for item in partition.stdout.decode().split() if '=' in item)
require(pf.get('State')=='UP' and pf.get('PreemptMode')=='OFF' and pf.get('OverSubscribe')=='NO' and pf.get('QoS')=='N/A','partition isolation differs')
scheduler=run(['scontrol','show','config'])
require(scheduler.returncode==0,'scheduler settings unavailable')
sf={k.strip():v.strip() for line in scheduler.stdout.decode().splitlines() if '=' in line for k,v in [line.split('=',1)]}
require(sf.get('PreemptType')=='preempt/none' and sf.get('PreemptMode')=='OFF','global preemption must be disabled')
print(json.dumps({'PreemptType':sf['PreemptType'],'PreemptMode':sf['PreemptMode'],'PrivateData':sf.get('PrivateData')},sort_keys=True),flush=True)
reservations=run(['scontrol','-o','show','reservation'])
require(reservations.returncode==0,'reservation inventory unavailable')
conflicting=[]
for line in reservations.stdout.decode().splitlines():
    if 'ReservationName=' not in line: continue
    fields=dict(item.split('=',1) for item in line.split() if '=' in item)
    nodes=fields.get('Nodes','')
    if not nodes or nodes in {'(null)','NONE'}: continue
    expanded=run(['scontrol','show','hostnames',nodes])
    require(expanded.returncode==0,'reservation host expansion failed')
    if 'ngu203' in expanded.stdout.decode().splitlines(): conflicting.append(line)
require(not conflicting,'target has a reservation; do not request its resources')
locks=root/'status/locks'
require(not locks.is_symlink() and (not locks.exists() or not list(locks.iterdir())),'existing execution lock or linked parent')
runs=root/'runs'
require(runs.is_dir() and not runs.is_symlink(),'run parent differs')
before_runs=sorted(p.name for p in runs.iterdir())
expected_v1=['DAILY_CAMELS_KNET_PER_BASIN_PILOT_04105700_A800_TRAIN3_SEQ13','DAILY_CAMELS_KNET_PER_BASIN_PILOT_08070200_A800_TRAIN1_SEQ18','DAILY_CAMELS_KNET_PER_BASIN_PILOT_09035800_A800_TRAIN1_SEQ24']
require(before_runs==expected_v1,'run namespace changed; refuse to collide with existing work')


runtime_audit=root/'node_recovery_20260907/task6_runtime_recovery1_seq39'
require(runtime_audit.is_dir() and runtime_audit.resolve()==runtime_audit,'accepted runtime audit path differs')
accepted_runtime_files={"pre_submit_baseline.json":{"bytes":1134,"sha256":"241848390d615e584ff988060a47082cf49718bb09225480426f26e8fc84b867"},"submission_receipt.json":{"bytes":368,"sha256":"1d1972caebc918eb33c915d83fa8f38af48f4f231805192f7108b758dd98a76a"},"runtime_gate.sh":{"bytes":4896,"sha256":"fba1762805311c2a28efd048dcfc61f47cf003c407671a02606f27dfff217913"},"slurm-223511.stdout":{"bytes":5852,"sha256":"ec4f54a3793bd43f13040cf948f3faaa952f9d94b4716a4ab8da06c1db65d316"},"slurm-223511.stderr":{"bytes":0,"sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},"gate_04105700.stdout":{"bytes":866,"sha256":"bd5bb9dfb86125e783f697a1d8038c9180cf2c687e3e8418a12ca02261671e29"},"gate_04105700.stderr":{"bytes":0,"sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},"gate_08070200.stdout":{"bytes":869,"sha256":"62be73432fab42846796924f688c98eb00d3b87f9301491fc0574cf34e7c70ca"},"gate_08070200.stderr":{"bytes":0,"sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},"gate_09035800.stdout":{"bytes":868,"sha256":"241ffc9b06b52886aac4cb6ba09705e42d52cc3bf2fea68045ba7177b64b7168"},"gate_09035800.stderr":{"bytes":0,"sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}}
for name,item in accepted_runtime_files.items():
    p=runtime_audit/name
    require(p.is_file() and not p.is_symlink(),'accepted runtime evidence missing or linked: '+name)
    b=p.read_bytes()
    require(len(b)==item['bytes'] and sha(b)==item['sha256'],'accepted runtime evidence differs: '+name)
require(not any((runtime_audit/'output_parent').iterdir()),'accepted runtime output parent changed')
prior=run(['sacct','-n','-P','-j','223511','--format=JobID,State,ExitCode,NodeList'])
emit('ACCEPTED_RUNTIME_ACCOUNTING',prior)
require(prior.returncode==0,'runtime accounting query failed')
prior_rows=[line.split('|') for line in prior.stdout.decode().splitlines() if line.startswith('223511|')]
require(len(prior_rows)==1 and prior_rows[0][:4]==['223511','COMPLETED','0:0','ngu203'],'runtime terminal state differs')
experiment_id='DAILY_CAMELS_KNET_PER_BASIN_PILOT_04105700_V2_20260902_A43'
execution_id='DAILY_CAMELS_KNET_PER_BASIN_PILOT_04105700_V2_20260902_A43_A800_TRAIN1_SEQ41'
config_rel='configs/daily_camels_knet_per_basin_pilot_v2_04105700.json'
config_bytes=(source/config_rel).read_bytes()
require(sha(config_bytes)=='d5d9814d2d3905eba308626236652d7dcbf6015f99c44ad05f67227b98255f38','sealed first configuration differs')
configuration=json.loads(config_bytes)
require(configuration['experiment_id']==experiment_id and configuration['basin_id']=='04105700' and configuration['model']['state_dimension']==7,'first basin identity differs')
require(len(configuration['source_sha256'])==18 and configuration['formal_evaluation_enabled'] is False,'first configuration policy differs')
sealed_script=source/'hpc/daily_camels_knet_per_basin/submit_train_gpu.slurm'
require(sha(sealed_script.read_bytes())=='f7ed33fd12a3db262f5d7f9b730fd841cd9de2f2a21d021536855f5602689bcf','sealed training launcher differs')
status=root/'status'
for parent in [status,status/'tmp',status/'cache',status/'locks',root/'node_recovery_20260907']:
    require(parent.is_dir() and parent.resolve()==parent and not parent.is_symlink(),'registered parent missing or linked: '+str(parent))
run_directory=runs/execution_id
audit_report=status/(execution_id+'.audit.json')
require(not run_directory.exists() and not run_directory.is_symlink(),'training run already exists')
require(not list(status.glob(execution_id+'*')),'training status evidence name already exists')
require(not (locks/(execution_id+'.lock')).exists(),'training owner lock already exists')
launch=root/'node_recovery_20260907/train_04105700_seq41'
require(launch.resolve()==launch and not launch.exists() and not launch.is_symlink(),'training launch directory already exists; do not submit again')
launch.mkdir()
for name in ['tmp','cache']: (launch/name).mkdir()
script="#!/usr/bin/env bash\n#SBATCH --job-name=kdpp-v2-train-04105700-seq41\n#SBATCH --partition=hgpu8\n#SBATCH --nodelist=ngu203\n#SBATCH --nodes=1\n#SBATCH --ntasks=1\n#SBATCH --cpus-per-task=4\n#SBATCH --gres=gpu:1\n#SBATCH --time=12:00:00\n#SBATCH --no-requeue\n#SBATCH --chdir=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901/deployments/DAILY_CAMELS_KNET_PER_BASIN_V2_BUNDLE_DEPLOY1_SEQ34/source\n#SBATCH --output=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901/status/DAILY_CAMELS_KNET_PER_BASIN_PILOT_04105700_V2_20260902_A43_A800_TRAIN1_SEQ41.slurm-%j.stdout\n#SBATCH --error=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901/status/DAILY_CAMELS_KNET_PER_BASIN_PILOT_04105700_V2_20260902_A43_A800_TRAIN1_SEQ41.slurm-%j.stderr\nset -eo pipefail\numask 077\n[[ \"${SLURM_RESTART_COUNT:-0}\" == 0 ]] || exit 82\n[[ -n \"${SLURM_JOB_ID:-}\" && \"$(hostname -s)\" == ngu203 ]] || exit 81\n[[ \"${SLURM_CPUS_PER_TASK:-}\" == 4 && -n \"${CUDA_VISIBLE_DEVICES:-}\" ]] || exit 83\nSOURCE=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901/deployments/DAILY_CAMELS_KNET_PER_BASIN_V2_BUNDLE_DEPLOY1_SEQ34/source\nAUDIT=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901/node_recovery_20260907/train_04105700_seq41\nROOT=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901\nPY=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python\n[[ \"${SLURM_SUBMIT_DIR:-}\" == \"$SOURCE\" ]] || exit 84\n[[ ! -e \"$ROOT/status/tmp/$SLURM_JOB_ID\" && ! -L \"$ROOT/status/tmp/$SLURM_JOB_ID\" ]] || exit 85\n[[ ! -e \"$ROOT/status/cache/$SLURM_JOB_ID\" && ! -L \"$ROOT/status/cache/$SLURM_JOB_ID\" ]] || exit 86\nexport PYTHONDONTWRITEBYTECODE=1 PYTHONOPTIMIZE=0 CUDA_CACHE_DISABLE=1\nexport OMP_NUM_THREADS=4 MKL_NUM_THREADS=4 OPENBLAS_NUM_THREADS=4 NUMEXPR_NUM_THREADS=4\nexport MKL_THREADING_LAYER=GNU MKL_SERVICE_FORCE_INTEL=1\nexport TMPDIR=\"$AUDIT/tmp\" XDG_CACHE_HOME=\"$AUDIT/cache\"\nexport PYTHONPATH=\"$SOURCE/src:$SOURCE\"\nexport PILOT_REMOTE_ROOT=\"$ROOT\"\nexport PILOT_CONFIG_RELATIVE=configs/daily_camels_knet_per_basin_pilot_v2_04105700.json\nexport PILOT_EXECUTION_ID=DAILY_CAMELS_KNET_PER_BASIN_PILOT_04105700_V2_20260902_A43_A800_TRAIN1_SEQ41\nexport PILOT_AUDIT_REPORT=\"$ROOT/status/$PILOT_EXECUTION_ID.audit.json\"\ncd \"$SOURCE\"\nprintf 'slurm_job_id=%s hostname=%s CUDA_VISIBLE_DEVICES=%s execution_id=%s\\n' \"$SLURM_JOB_ID\" \"$(hostname -s)\" \"${CUDA_VISIBLE_DEVICES:-}\" \"$PILOT_EXECUTION_ID\"\ndate --iso-8601=seconds\n\"$PY\" -B -u - <<'RESOURCE_GATE'\nimport json, os, pathlib, subprocess, sys\nr=subprocess.run(['nvidia-smi','--query-compute-apps=gpu_uuid,pid,process_name,used_gpu_memory','--format=csv,noheader,nounits'],capture_output=True,text=True,timeout=30,check=False)\nprint(json.dumps(dict(stage='whole_node_existing_compute_processes',exit_code=r.returncode,stdout=r.stdout,stderr=r.stderr)),flush=True)\nif r.returncode != 0 or r.stdout.strip():\n    raise RuntimeError('pre-existing GPU compute process or unverifiable query; no process is cancelled')\nmem={}\nfor line in pathlib.Path('/proc/meminfo').read_text().splitlines():\n    key,value=line.split(':',1)\n    if key in ('MemTotal','MemAvailable'): mem[key]=int(value.strip().split()[0])*1024\nprint(json.dumps(dict(stage='host_memory',**mem)),flush=True)\nif mem.get('MemAvailable',0)<32*1024**3:\n    raise RuntimeError('less than 32 GiB available host memory; no training launched')\ng=subprocess.run(['nvidia-smi','--query-gpu=uuid,name,memory.total,memory.used,memory.free,utilization.gpu','--format=csv,noheader,nounits'],capture_output=True,text=True,timeout=30,check=False)\nprint(json.dumps(dict(stage='whole_node_gpu_memory',exit_code=g.returncode,stdout=g.stdout,stderr=g.stderr)),flush=True)\nif g.returncode != 0: raise RuntimeError('GPU memory query failed')\nimport numpy, torch\ninfo=dict(stage='allocated_device_identity',python=sys.version.split()[0],numpy=numpy.__version__,torch=torch.__version__,cuda_available=torch.cuda.is_available(),visible_cuda_devices=torch.cuda.device_count())\nif not info['cuda_available'] or info['visible_cuda_devices'] != 1:\n    print(json.dumps(info),flush=True)\n    raise RuntimeError('exactly one allocated visible CUDA device required')\ninfo['gpu_name']=torch.cuda.get_device_name(0)\ninfo['gpu_free_bytes'],info['gpu_total_bytes']=torch.cuda.mem_get_info()\nprint(json.dumps(info),flush=True)\nif info['python']!='3.11.13' or info['numpy']!='2.3.3' or info['torch'].split('+')[0]!='2.4.0' or info['gpu_name']!='NVIDIA A800-SXM4-80GB':\n    raise RuntimeError('registered device or interpreter mismatch')\nif info['gpu_free_bytes']<64*1024**3:\n    raise RuntimeError('less than 64 GiB free on allocated A800; no experiment launched')\nRESOURCE_GATE\necho 'SEALED_TRAINING_WRAPPER_BEGIN basin=04105700 requested_epochs=80'\nexec bash \"$SOURCE/hpc/daily_camels_knet_per_basin/submit_train_gpu.slurm\"\n"
script_bytes=script.encode()
launch_script=launch/'train.sh'
with launch_script.open('xb') as f: f.write(script_bytes)
baseline=dict(request_sequence=41,experiment_id=experiment_id,execution_id=execution_id,basin_id='04105700',state_dimension=7,configuration_sha256=sha(config_bytes),source_root=str(source),source_sha256=configuration['source_sha256'],archive_sha256='1b78bbae823d55859391a6cdee3b9fbe8a40203e5140b8795105a8617592b7fd',deployed_files=51,run_directory=str(run_directory),audit_report=str(audit_report),before_runs=before_runs,node='ngu203',partition='hgpu8',gpu_name='NVIDIA A800-SXM4-80GB',cpus=4,gpus=1,time_limit='12:00:00',requeue=False,global_preemption='OFF',training_attempt=1,training_epochs=80,recovery_requests_used=0,sealed_training_script_sha256='f7ed33fd12a3db262f5d7f9b730fd841cd9de2f2a21d021536855f5602689bcf',node_wrapper_sha256=sha(script_bytes),node_wrapper_bytes=len(script_bytes),accepted_runtime_job='223511',accepted_runtime_result_sha256='a33d3da33fbebca687c4b611367a5d15c7f9d5c80e03d1071834a932cc0b2049',accepted_runtime_files=accepted_runtime_files,formal_evaluation_access_count=0)
baseline_bytes=(json.dumps(baseline,sort_keys=True,allow_nan=False)+'\n').encode()
with (launch/'pre_submit_baseline.json').open('xb') as f: f.write(baseline_bytes)
print(json.dumps(dict(pre_submit_baseline=baseline,baseline_sha256=sha(baseline_bytes)),sort_keys=True),flush=True)
submission=run(['sbatch',str(launch_script)],cwd=str(source),timeout=60)
emit('SBATCH_FIRST_BASIN_TRAINING_ONCE',submission)
job_matches=re.findall(r'(?m)^Submitted batch job ([0-9]+)\s*$',submission.stdout.decode())
if not job_matches and re.fullmatch(r'[0-9]+(?:;[A-Za-z0-9_.-]+)?\s*',submission.stdout.decode()):
    job_matches=[submission.stdout.decode().strip().split(';')[0]]
receipt=dict(request_sequence=41,execution_id=execution_id,submission_exit_code=submission.returncode,stdout=submission.stdout.decode(),stderr=submission.stderr.decode(),job_matches=job_matches,baseline_sha256=sha(baseline_bytes),node_wrapper_sha256=sha(script_bytes),training_submissions=1)
with (launch/'submission_receipt.json').open('xb') as f: f.write((json.dumps(receipt,sort_keys=True)+'\n').encode())
require(submission.returncode==0 and len(job_matches)==1,'submission ambiguous or failed; read-only reconciliation only; no fresh execution or resubmission')
job_id=job_matches[0]
emit('SUBMITTED_TRAINING_CONTROLLER_RECORD',run(['scontrol','show','job',job_id]))
verify_source()
after_runs=sorted(p.name for p in runs.iterdir())
require(set(after_runs) in [set(before_runs),set(before_runs)|{execution_id}],'unrelated run namespace changed')
print(json.dumps(dict(status='TRAINING_SUBMITTED_NOT_YET_VERIFIED_RUNNING',request_sequence=41,job_id=job_id,execution_id=execution_id,experiment_id=experiment_id,basin_id='04105700',node='ngu203',run_directory=str(run_directory),launch_directory=str(launch),audit_report=str(audit_report),baseline_sha256=sha(baseline_bytes),node_wrapper_sha256=sha(script_bytes),training_submissions=1,formal_evaluation_access_count=0),sort_keys=True),flush=True)

PY_SUBMISSION
