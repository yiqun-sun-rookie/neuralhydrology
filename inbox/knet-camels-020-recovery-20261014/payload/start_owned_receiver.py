"""Restore only this experiment's two channels in an independent transport root.

No shared receiver/environment changes. Original seq29/deploy guard retains the
single-submission protection. Model computation remains inside its Slurm job.
"""
import os,sys,json,hashlib,urllib.request,subprocess,datetime,time,fcntl
from pathlib import Path

ROOT=Path('/data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/020_snow_training_20261014_001/transport_recovery')
CHANNELS=['knet-camels-hpc-20261012-001','knet-camels-020-recovery-20261014']
SOURCE_COMMIT='0a3e0f4342454f2f14a28bdb3279050bb1de4b40'
SOURCE_SHA='192204831dc622b457e9c80a9331ca1d9659fbe4641243681fa52d4ef3030a08'
PYTHON='/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python'
def emit(event,**data):
    payload=dict(event=event,utc=datetime.datetime.now(datetime.timezone.utc).isoformat());payload.update(data)
    print(json.dumps(payload),flush=True)
def run(args,timeout=180,cwd=None):
    reply=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,timeout=timeout,cwd=cwd)
    if reply.returncode:raise RuntimeError('Command failed: '+repr(args)+'\n'+reply.stdout+'\n'+reply.stderr)
    return reply.stdout
def verify_path(path):
    assert path.is_absolute() and '..' not in path.parts
    for p in (path,*path.parents):assert not p.is_symlink(),'linked path '+str(p)
def raw(name):
    url='https://raw.githubusercontent.com/yiqun-sun-rookie/neuralhydrology/'+SOURCE_COMMIT+'/'+name
    with urllib.request.urlopen(url,timeout=60) as response:return response.read()
def save_exact(path,value):
    verify_path(path)
    if path.exists():assert path.read_bytes()==value,'existing transport file differs: '+str(path)
    else:
        with path.open('xb') as handle:handle.write(value)
def serve():
    lock=(ROOT/'receiver.lock').open('a')
    try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    except BlockingIOError:emit('OWN_RECEIVER_ALREADY_RUNNING');return
    os.nice(10)
    record=dict(pid=os.getpid(),process_start_ticks=Path('/proc/self/stat').read_text().split()[21],
        utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),channels=CHANNELS,
        original_sequence=29,shared_runner_changed=False,shared_environment_changed=False,
        scientific_conditions_changed=False,receiver_source_sha256=SOURCE_SHA)
    (ROOT/'receiver_started.json').write_text(json.dumps(record,indent=2))
    emit('OWN_RECEIVER_STARTED',**record)
    env=dict(os.environ,MAILBOX_DIR=str(ROOT/'repo'),STAGING=str(ROOT/'staging'),
        LOCKDIR=str(ROOT/'pushlock'),HPC_RUNNER_DETACHED='1',MAX_WORKERS='2',POLL_INTERVAL='20',GIT_TIMEOUT='120')
    reply=subprocess.run(['bash',str(ROOT/'owned_receiver.sh')],cwd=ROOT/'repo',env=env)
    emit('OWN_RECEIVER_EXITED',exit_code=reply.returncode)
    raise SystemExit(reply.returncode)

if '--serve' in sys.argv:serve();raise SystemExit(0)
verify_path(ROOT);ROOT.mkdir(parents=True,exist_ok=True)
main_lock=(ROOT/'bootstrap.lock').open('a')
try:fcntl.flock(main_lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
except BlockingIOError:emit('BOOTSTRAP_ALREADY_RUNNING');raise SystemExit(0)
started=ROOT/'receiver_started.json'
if started.exists():
    previous=json.loads(started.read_text());pid=previous['pid']
    try:command=Path('/proc/'+str(pid)+'/cmdline').read_bytes()
    except FileNotFoundError:command=b''
    if str(ROOT/'start_owned_receiver.py').encode() in command:
        emit('OWN_RECEIVER_ALREADY_RUNNING',pid=pid);raise SystemExit(0)
original=raw('runner2.sh');assert hashlib.sha256(original).hexdigest()==SOURCE_SHA
source=original.decode()
before='for d in inbox/*/; do'
after='for d in '+' '.join('inbox/'+c+'/' for c in CHANNELS)+'; do'
assert source.count(before)==1
source=source.replace(before,after)
default='    [ -f inbox/seq ] && [ -f inbox/cmd.sh ] && CHANNELS="$CHANNELS inbox"'
assert source.count(default)==1;source=source.replace(default,'    # This receiver never scans the legacy default channel.')
assert source.count('git add -A outbox')==2
source=source.replace('git add -A outbox','git add "outbox/$CH/result_${SEQ}.txt"')
save_exact(ROOT/'owned_receiver.sh',source.encode())
save_exact(ROOT/'original_receiver_source.sh',original)
save_exact(ROOT/'start_owned_receiver.py',Path(__file__).read_bytes())
repo=ROOT/'repo'
if not (repo/'.git').is_dir():
    emit('ISOLATED_REPOSITORY_PREPARATION')
    run(['git','clone','--shared','--no-checkout',str(Path.home()/'hpc_mailbox'),str(repo)],timeout=120)
run(['git','config','remote.origin.url','git@github.com:yiqun-sun-rookie/neuralhydrology.git'],cwd=repo)
for name in ['gc.auto','gc.autoDetach']:
    run(['git','config',name,'0' if name=='gc.auto' else 'false'],cwd=repo)
for name,fallback in [('user.name','sunyiq'),('user.email','yiqun.sun.hydro.gee@gmail.com')]:
    p=subprocess.run(['git','config','--get',name],cwd=Path.home()/'hpc_mailbox',capture_output=True,text=True)
    run(['git','config',name,p.stdout.strip() or fallback],cwd=repo)
run(['git','config','core.sparseCheckout','true'],cwd=repo)
sparse='\n'.join(['/.gitattributes',*['/inbox/'+c+'/' for c in CHANNELS],*['/outbox/'+c+'/' for c in CHANNELS]])+'\n'
(repo/'.git/info/sparse-checkout').write_text(sparse)
emit('FETCH_LATEST_MAILBOX_METADATA')
run(['git','fetch','--depth=1','-q','origin','+hpc-mailbox:refs/remotes/origin/hpc-mailbox'],timeout=300,cwd=repo)
run(['git','checkout','-B','hpc-mailbox','refs/remotes/origin/hpc-mailbox'],timeout=120,cwd=repo)
seq=(repo/'inbox'/CHANNELS[0]/'seq').read_text().strip()
assert seq=='29','Primary sequence changed; inspect before activation.'
cmd=(repo/'inbox'/CHANNELS[0]/'cmd.sh').read_bytes()
assert hashlib.sha256(cmd).hexdigest()=='5b5a66727a106f6fa07541f93f157c7b46b715aff228a5e97b41941524d9ea63'
save_exact(ROOT/'activation_review.json',(json.dumps(dict(status='PASS',channels=CHANNELS,
    original_seq29_command_exact=True,new_scientific_submissions_issued_by_bootstrap=0,
    independent_repository=True,independent_staging=True,independent_pushlock=True,
    no_shared_receiver_restart=True,science_files_unchanged=True),indent=2)+'\n').encode())
emit('ACTIVATION_REVIEW_PASS')
with (ROOT/'receiver.log').open('ab') as log:
    child=subprocess.Popen([PYTHON,'-u','-B',str(ROOT/'start_owned_receiver.py'),'--serve'],
        stdout=log,stderr=subprocess.STDOUT,stdin=subprocess.DEVNULL,start_new_session=True)
emit('OWN_RECEIVER_LAUNCHED',pid=child.pid,log=str(ROOT/'receiver.log'))
for i in range(20):
    if child.poll() is not None:raise RuntimeError('Owned receiver exited; inspect '+str(ROOT/'receiver.log'))
    time.sleep(1)
print((ROOT/'receiver.log').read_text(errors='replace')[-7000:])
emit('BOOTSTRAP_COMPLETE',original_training_submission='Only the existing pending seq29 is eligible; no new seq or duplicate job.')
