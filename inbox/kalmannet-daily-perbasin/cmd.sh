#!/usr/bin/env bash
set -euo pipefail
sequence=35
echo "channel=kalmannet-daily-perbasin sequence=${sequence} purpose=v2-task6-no-update-runtime-gate"
date --iso-8601=seconds
hostname
export PYTHONDONTWRITEBYTECODE=1 PYTHONOPTIMIZE=0
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
import hashlib, json, os, pathlib, re, subprocess, sys, time
root = pathlib.Path('/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901')
source = root / 'deployments/DAILY_CAMELS_KNET_PER_BASIN_V2_BUNDLE_DEPLOY1_SEQ34/source'
sequence = 35
sha = lambda b: hashlib.sha256(b).hexdigest()
def require(value, message):
    if not value: raise RuntimeError(message)
def run(args, **kwargs):
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
queue = run(['squeue', '-h', '-u', str(os.getuid()), '-o', '%i|%200j|%T|%N'])
emit('CURRENT_USER_QUEUE', queue)
require(queue.returncode == 0, 'queue query failed')
related = [line for line in queue.stdout.decode().splitlines() if re.search(r'kdpp|DAILY_CAMELS_KNET_PER_BASIN|daily.camels.*per.basin|kalmannet.daily.perbasin', line, re.I)]
print('related_active_job_count=' + str(len(related)), flush=True)
require(not related, 'related active job exists')
node = run(['sinfo', '-N', '-n', 'ngu202', '-o', '%N|%P|%T|%G|%C|%m'])
emit('TARGET_NODE_STATE', node)
require(node.returncode == 0, 'node query failed')
help_check = run(['sbatch', '--help'])
require(help_check.returncode == 0 and all(option in help_check.stdout.decode() for option in ('--deadline', '--wait', '--no-requeue')), 'required scheduler options unavailable')
locks = root / 'status/locks'
require(not locks.is_symlink(), 'lock parent is linked')
require(not locks.exists() or not list(locks.iterdir()), 'existing execution lock present')
runs = root / 'runs'
require(not runs.is_symlink(), 'run parent is linked')
before_runs = sorted(p.name for p in runs.iterdir()) if runs.is_dir() else None
audits = root / 'runtime_gate_audits'
require(not audits.is_symlink() and audits.resolve() == audits, 'audit parent link or escape')
if not audits.exists(): audits.mkdir()
require(audits.is_dir(), 'audit parent is not a directory')
audit = audits / 'V2_TASK6_SEQ35'
require(not audit.exists() and not audit.is_symlink(), 'audit target already exists')
audit.mkdir()
for name in ('output_parent', 'tmp', 'cache'): (audit / name).mkdir()
script = r'''#!/usr/bin/env bash
set -euo pipefail
set -o noclobber
[[ "${SLURM_RESTART_COUNT:-0}" == 0 ]] || exit 82
SOURCE=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901/deployments/DAILY_CAMELS_KNET_PER_BASIN_V2_BUNDLE_DEPLOY1_SEQ34/source
AUDIT=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901/runtime_gate_audits/V2_TASK6_SEQ35
PY=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
[[ -n "${SLURM_JOB_ID:-}" && "$(hostname -s)" == ngu202 ]] || exit 81
export PYTHONDONTWRITEBYTECODE=1 PYTHONOPTIMIZE=0
export OMP_NUM_THREADS=4 MKL_NUM_THREADS=4 OPENBLAS_NUM_THREADS=4 NUMEXPR_NUM_THREADS=4
export TMPDIR="$AUDIT/tmp" XDG_CACHE_HOME="$AUDIT/cache"
export CUDA_CACHE_DISABLE=1
export PYTHONPATH="$SOURCE/src:$SOURCE"
cd "$SOURCE"
printf 'slurm_job_id=%s hostname=%s CUDA_VISIBLE_DEVICES=%s\n' "$SLURM_JOB_ID" "$(hostname -s)" "${CUDA_VISIBLE_DEVICES:-}"
date --iso-8601=seconds
free -b
nvidia-smi --query-gpu=uuid,name,memory.total,memory.used,memory.free,utilization.gpu --format=csv,noheader,nounits
"$PY" -B -u -c 'import sys,json,numpy,torch; print(json.dumps({"python":sys.version,"numpy":numpy.__version__,"torch":torch.__version__,"cuda_available":torch.cuda.is_available(),"visible_cuda_devices":torch.cuda.device_count()},sort_keys=True))'
for basin in 04105700 08070200 09035800; do
    echo "RUNTIME_GATE_BEGIN basin=$basin"
    set +e
    "$PY" -B -u scripts/check_daily_camels_knet_per_basin_runtime.py \
        --config "$SOURCE/configs/daily_camels_knet_per_basin_pilot_v2_${basin}.json" \
        --output-parent "$AUDIT/output_parent" \
        --execution-id "DAILY_CAMELS_KNET_PER_BASIN_PILOT_${basin}_V2_TASK6_RUNTIME_GATE_SEQ35" \
        --repository-root "$SOURCE" --device cuda > "$AUDIT/gate_${basin}.stdout" 2> "$AUDIT/gate_${basin}.stderr"
    gate_exit=$?
    set -e
    cat "$AUDIT/gate_${basin}.stdout"
    cat "$AUDIT/gate_${basin}.stderr" >&2
    echo "RUNTIME_GATE_END basin=$basin exit_code=$gate_exit"
    [[ "$gate_exit" == 0 ]] || exit "$gate_exit"
done
echo 'TASK6_THREE_RUNTIME_CHECKS_FINISHED optimizer_steps=0 training_submissions=0'
'''
job_script = audit / 'runtime_gate.sh'
with job_script.open('xb') as f: f.write(script.encode('utf-8'))
print(json.dumps({'runtime_script_path': str(job_script), 'runtime_script_sha256': sha(script.encode()), 'runtime_script_bytes': len(script.encode()), 'training_submissions': 0}, sort_keys=True), flush=True)
submission = run(['sbatch', '--parsable', '--wait', '--deadline=now+20minutes', '--no-requeue',
                  '--job-name=kdpp-v2-runtime-seq35', '--partition=hgpu8', '--nodelist=ngu202',
                  '--nodes=1', '--ntasks=1', '--cpus-per-task=4', '--gres=gpu:1', '--time=00:15:00',
                  '--chdir=' + str(source), '--output=' + str(audit / 'slurm-%j.stdout'),
                  '--error=' + str(audit / 'slurm-%j.stderr'), str(job_script)])
emit('SBATCH_NO_TRAINING_RUNTIME_GATE', submission)
for path in sorted(audit.iterdir()):
    if path.is_file() and path.suffix in ('.stdout', '.stderr'):
        data = path.read_bytes()
        print(json.dumps({'file': str(path), 'bytes': len(data), 'sha256': sha(data)}, sort_keys=True), flush=True)
        print(data.decode('utf-8'), end='', flush=True)
verify_source()
after_runs = sorted(p.name for p in runs.iterdir()) if runs.is_dir() else None
require(before_runs == after_runs, 'training run directories changed')
require(not list((audit / 'output_parent').iterdir()), 'runtime gate created training output')
require(submission.returncode == 0, 'runtime allocation or job failed; no retry')
job_text = submission.stdout.decode().strip()
require(re.fullmatch(r'[0-9]+(?:;[A-Za-z0-9_.-]+)?', job_text) is not None, 'ambiguous sbatch job identity')
job_id = job_text.split(';')[0]
account = None
terminal = None
for attempt in range(7):
    account = run(['sacct', '-X', '-n', '-P', '-j', job_id, '--format=JobIDRaw,JobName%80,State,ExitCode,NodeList,AllocTRES%120'])
    emit('RUNTIME_JOB_ACCOUNTING_' + str(attempt), account)
    require(account.returncode == 0, 'accounting query failed')
    rows = [line.split('|') for line in account.stdout.decode().splitlines()]
    own = [row for row in rows if row and row[0] == job_id]
    if len(own) == 1 and own[0][2] == 'COMPLETED' and own[0][3] == '0:0':
        terminal = own[0]
        break
    if attempt < 6: time.sleep(5)
require(terminal is not None, 'complete scheduler terminal evidence unavailable')
gate_results = []
for basin, dimension in (('04105700', 7), ('08070200', 11), ('09035800', 18)):
    lines = (audit / ('gate_' + basin + '.stdout')).read_text().splitlines()
    records = [json.loads(line) for line in lines if line.startswith('{')]
    require(len(records) == 1, 'runtime result missing or ambiguous')
    value = records[0]
    require(value['schema_version'] == 'daily_camels_knet_per_basin_runtime_gate_v2' and value['status'] == 'PASS', 'runtime failed')
    require(value['basin_id'] == basin and value['state_dimension'] == dimension, 'runtime identity mismatch')
    require(value['optimizer_steps'] == value['formal_evaluation_access_count'] == 0, 'runtime operation boundary failed')
    require(value['gpu_name'] == 'NVIDIA A800-SXM4-80GB' and value['device'] == 'cuda', 'wrong runtime device')
    require(all(value[k] is True for k in ('exact_active_mask_no_padding', 'causal_future_observation_test', 'finite_nonzero_gradient_test', 'checkpoint_restore_test', 'epoch_zero_joint_resume_test')), 'runtime subtest failed')
    gate_results.append(value)
print(json.dumps({'status': 'TASK6_RUNTIME_GATE_PASS', 'request_sequence': sequence, 'job_id': job_id,
                  'job_terminal_row': terminal, 'audit_directory': str(audit), 'source_root': str(source),
                  'runtime_results': gate_results, 'training_submissions': 0, 'optimizer_steps': 0,
                  'formal_evaluation_access_count': 0, 'deployed_member_mismatches': 0}, sort_keys=True, allow_nan=False), flush=True)
PY
