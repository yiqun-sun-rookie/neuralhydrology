#!/usr/bin/env bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1 PYTHONOPTIMIZE=0
printf '%s\n' 'channel=kalmannet-daily-perbasin sequence=39 purpose=task6-runtime-recovery1-on-ngu203-no-training'
date -Is
hostname
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY_SUBMISSION'
import hashlib, json, os, pathlib, re, subprocess, sys, time
root = pathlib.Path('/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901')
source = root / 'deployments/DAILY_CAMELS_KNET_PER_BASIN_V2_BUNDLE_DEPLOY1_SEQ34/source'
sequence = 39
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
recovery_root=root/'node_recovery_20260907'
require(recovery_root.resolve()==recovery_root and not recovery_root.exists() and not recovery_root.is_symlink(),'recovery root already exists or linked; do not repeat recovery')
audit=recovery_root/'task6_runtime_recovery1_seq39'
recovery_root.mkdir()
audit.mkdir()
for member in ('output_parent','tmp','cache'): (audit/member).mkdir()
script = "#!/usr/bin/env bash\n#SBATCH --job-name=kdpp-v2-runtime-recovery1-seq39\n#SBATCH --partition=hgpu8\n#SBATCH --nodelist=ngu203\n#SBATCH --nodes=1\n#SBATCH --ntasks=1\n#SBATCH --cpus-per-task=4\n#SBATCH --gres=gpu:1\n#SBATCH --time=00:15:00\n#SBATCH --deadline=now+20minutes\n#SBATCH --no-requeue\n#SBATCH --chdir=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901/deployments/DAILY_CAMELS_KNET_PER_BASIN_V2_BUNDLE_DEPLOY1_SEQ34/source\n#SBATCH --output=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901/node_recovery_20260907/task6_runtime_recovery1_seq39/slurm-%j.stdout\n#SBATCH --error=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901/node_recovery_20260907/task6_runtime_recovery1_seq39/slurm-%j.stderr\nset -eo pipefail\nset -o noclobber\numask 077\n[[ \"${SLURM_RESTART_COUNT:-0}\" == 0 ]] || exit 82\n[[ -n \"${SLURM_JOB_ID:-}\" && \"$(hostname -s)\" == ngu203 ]] || exit 81\n[[ \"${SLURM_CPUS_PER_TASK:-}\" == 4 && -n \"${CUDA_VISIBLE_DEVICES:-}\" ]] || exit 83\nSOURCE=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901/deployments/DAILY_CAMELS_KNET_PER_BASIN_V2_BUNDLE_DEPLOY1_SEQ34/source\nAUDIT=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901/node_recovery_20260907/task6_runtime_recovery1_seq39\nPY=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python\nexport PYTHONDONTWRITEBYTECODE=1 PYTHONOPTIMIZE=0\nexport OMP_NUM_THREADS=4 MKL_NUM_THREADS=4 OPENBLAS_NUM_THREADS=4 NUMEXPR_NUM_THREADS=4\nexport MKL_THREADING_LAYER=GNU MKL_SERVICE_FORCE_INTEL=1\nexport TMPDIR=\"$AUDIT/tmp\" XDG_CACHE_HOME=\"$AUDIT/cache\" CUDA_CACHE_DISABLE=1\nexport PYTHONPATH=\"$SOURCE/src:$SOURCE\"\ncd \"$SOURCE\"\nprintf 'slurm_job_id=%s hostname=%s CUDA_VISIBLE_DEVICES=%s\\n' \"$SLURM_JOB_ID\" \"$(hostname -s)\" \"${CUDA_VISIBLE_DEVICES:-}\"\ndate --iso-8601=seconds\n\"$PY\" -B -u - <<'RESOURCE_GATE'\nimport json, os, pathlib, subprocess, sys\nr=subprocess.run(['nvidia-smi','--query-compute-apps=gpu_uuid,pid,process_name,used_gpu_memory','--format=csv,noheader,nounits'],capture_output=True,text=True,timeout=30,check=False)\nprint(json.dumps(dict(stage='whole_node_existing_compute_processes',exit_code=r.returncode,stdout=r.stdout,stderr=r.stderr)),flush=True)\nif r.returncode != 0 or r.stdout.strip():\n    raise RuntimeError('pre-existing GPU compute process or unverifiable query; no process is cancelled')\nmem={}\nfor line in pathlib.Path('/proc/meminfo').read_text().splitlines():\n    key,value=line.split(':',1)\n    if key in ('MemTotal','MemAvailable'): mem[key]=int(value.strip().split()[0])*1024\nprint(json.dumps(dict(stage='host_memory',**mem)),flush=True)\nif mem.get('MemAvailable',0)<32*1024**3:\n    raise RuntimeError('less than 32 GiB available host memory; no training launched')\ng=subprocess.run(['nvidia-smi','--query-gpu=uuid,name,memory.total,memory.used,memory.free,utilization.gpu','--format=csv,noheader,nounits'],capture_output=True,text=True,timeout=30,check=False)\nprint(json.dumps(dict(stage='whole_node_gpu_memory',exit_code=g.returncode,stdout=g.stdout,stderr=g.stderr)),flush=True)\nif g.returncode != 0: raise RuntimeError('GPU memory query failed')\nimport numpy, torch\ninfo=dict(stage='allocated_device_identity',python=sys.version.split()[0],numpy=numpy.__version__,torch=torch.__version__,cuda_available=torch.cuda.is_available(),visible_cuda_devices=torch.cuda.device_count())\nif not info['cuda_available'] or info['visible_cuda_devices'] != 1:\n    print(json.dumps(info),flush=True)\n    raise RuntimeError('exactly one allocated visible CUDA device required')\ninfo['gpu_name']=torch.cuda.get_device_name(0)\ninfo['gpu_free_bytes'],info['gpu_total_bytes']=torch.cuda.mem_get_info()\nprint(json.dumps(info),flush=True)\nif info['python']!='3.11.13' or info['numpy']!='2.3.3' or info['torch'].split('+')[0]!='2.4.0' or info['gpu_name']!='NVIDIA A800-SXM4-80GB':\n    raise RuntimeError('registered device or interpreter mismatch')\nif info['gpu_free_bytes']<64*1024**3:\n    raise RuntimeError('less than 64 GiB free on allocated A800; no experiment launched')\nRESOURCE_GATE\nfor basin in 04105700 08070200 09035800; do\n    echo \"RUNTIME_GATE_BEGIN basin=$basin\"\n    set +e\n    \"$PY\" -B -u scripts/check_daily_camels_knet_per_basin_runtime.py \\\n        --config \"$SOURCE/configs/daily_camels_knet_per_basin_pilot_v2_${basin}.json\" \\\n        --output-parent \"$AUDIT/output_parent\" \\\n        --execution-id \"DAILY_CAMELS_KNET_PER_BASIN_PILOT_${basin}_V2_TASK6_RUNTIME_RECOVERY1_SEQ39\" \\\n        --repository-root \"$SOURCE\" --device cuda > \"$AUDIT/gate_${basin}.stdout\" 2> \"$AUDIT/gate_${basin}.stderr\"\n    gate_exit=$?\n    set -e\n    cat \"$AUDIT/gate_${basin}.stdout\"\n    cat \"$AUDIT/gate_${basin}.stderr\" >&2\n    echo \"RUNTIME_GATE_END basin=$basin exit_code=$gate_exit\"\n    [[ \"$gate_exit\" == 0 ]] || exit \"$gate_exit\"\ndone\necho 'TASK6_THREE_RUNTIME_CHECKS_FINISHED optimizer_steps=0 training_submissions=0'\nscontrol show job \"$SLURM_JOB_ID\"\n"
job_script=audit/'runtime_gate.sh'
with job_script.open('xb') as f: f.write(script.encode())
baseline={'request_sequence':39,'predecessor_runtime_request':35,'predecessor_job_id':'223507','recovery_attempt':1,'before_runs':before_runs,'source_root':str(source),'archive_sha256':'1b78bbae823d55859391a6cdee3b9fbe8a40203e5140b8795105a8617592b7fd','internal_manifest_sha256':'5abaa07cfc00e2795a91a8cd70bb793e5cf362971fd04a2de44cbf3e15fa587f','deployed_files':51,'runtime_script_path':str(job_script),'runtime_script_sha256':sha(script.encode()),'runtime_script_bytes':len(script.encode()),'node':'ngu203','partition':'hgpu8','gpu_name':'NVIDIA A800-SXM4-80GB','training_submissions':0,'global_preemption':'OFF','old_failure_preserved':True}
baseline_bytes=(json.dumps(baseline,sort_keys=True,allow_nan=False)+'\n').encode()
with (audit/'pre_submit_baseline.json').open('xb') as f: f.write(baseline_bytes)
print(json.dumps({'pre_submit_baseline':baseline,'baseline_sha256':sha(baseline_bytes)},sort_keys=True),flush=True)
submission=run(['sbatch',str(job_script)],timeout=60)
emit('SBATCH_NO_TRAINING_RUNTIME_RECOVERY1',submission)
job_matches=re.findall(r'(?m)^Submitted batch job ([0-9]+)\s*$',submission.stdout.decode())
if not job_matches and re.fullmatch(r'[0-9]+(?:;[A-Za-z0-9_.-]+)?\s*',submission.stdout.decode()):
    job_matches=[submission.stdout.decode().strip().split(';')[0]]
receipt={'request_sequence':39,'submission_exit_code':submission.returncode,'stdout':submission.stdout.decode(),'stderr':submission.stderr.decode(),'job_matches':job_matches,'baseline_sha256':sha(baseline_bytes),'runtime_script_sha256':sha(script.encode()),'training_submissions':0,'runtime_submissions':1}
with (audit/'submission_receipt.json').open('xb') as f: f.write((json.dumps(receipt,sort_keys=True)+'\n').encode())
require(submission.returncode==0 and len(job_matches)==1,'submission ambiguous or failed; read-only reconciliation only, do not resubmit')
job_id=job_matches[0]
account=run(['scontrol','show','job',job_id])
emit('SUBMITTED_JOB_CONTROLLER_RECORD',account)
verify_source()
require(sorted(p.name for p in runs.iterdir())==before_runs,'training runs changed after non-training submission')
print(json.dumps({'status':'TASK6_RUNTIME_RECOVERY_SUBMITTED_NOT_PASSED','request_sequence':39,'job_id':job_id,'node':'ngu203','audit_directory':str(audit),'source_root':str(source),'baseline_sha256':sha(baseline_bytes),'runtime_script_sha256':sha(script.encode()),'training_submissions':0,'runtime_submissions':1,'formal_evaluation_access_count':0},sort_keys=True),flush=True)
PY_SUBMISSION
