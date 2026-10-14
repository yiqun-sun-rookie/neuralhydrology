"""Inspect saved receipts, then restore the unchanged shared mailbox receiver.

No sbatch, cancellation, model execution, or command/sequence publication.
Ambiguous staging or another live receiver stops recovery before launch.
"""
import datetime
import fcntl
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

HOME_DIR = Path('/data1/home/sunyiq')
REPO = HOME_DIR / 'hpc_mailbox'
STAGING = HOME_DIR / '.hpc_mailbox_staging'
PUSHLOCK = HOME_DIR / '.hpc_mailbox_pushlock'
BASE = HOME_DIR / 'knet_camels_hpc_20261012_001/attempts/020_snow_training_20261014_001'
ROOT = BASE / 'original_receiver_recovery'
SOURCE_SHA = '192204831dc622b457e9c80a9331ca1d9659fbe4641243681fa52d4ef3030a08'
OWN_CHANNEL = 'knet-camels-hpc-20261012-001'
OWN_COMMAND_SHA = '5b5a66727a106f6fa07541f93f157c7b46b715aff228a5e97b41941524d9ea63'


def checked(path):
    assert path.is_absolute() and '..' not in path.parts
    for parent in (path, *path.parents):
        if parent.is_symlink():
            raise RuntimeError('Linked recovery path: ' + str(parent))
    return path


def run(args, timeout=45, cwd=REPO, required=True):
    reply = subprocess.run(args, cwd=cwd, capture_output=True, timeout=timeout)
    if required and reply.returncode:
        raise RuntimeError(repr(args) + ': ' + reply.stderr.decode(errors='replace')[-3000:])
    return reply


def git(*args, required=True):
    return run(['git', '-c', 'gc.auto=0', *args], required=required)


def active_processes():
    found = []
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit() or int(proc.name) == os.getpid():
            continue
        try:
            if proc.stat().st_uid != os.getuid():
                continue
            command = (proc / 'cmdline').read_bytes().replace(b'\0', b' ').decode(errors='replace')
            receiver = '.hpc_runner_active.sh' in command or re.search(r'(?:^|\s)\S*runner2\.sh(?:\s|$)', command)
            isolated = '--serve' in command and any(x in command for x in ('start_git.py', 'start_git_v2.py', 'start_owned_receiver.py'))
            comm = (proc / 'comm').read_text().strip()
            shared_git = comm.startswith('git') and (proc / 'cwd').resolve() == REPO
            if receiver or isolated or shared_git:
                found.append({'pid': int(proc.name), 'comm': comm, 'receiver': bool(receiver or isolated), 'shared_git': shared_git})
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue
    return found


def emit(event, **data):
    print(json.dumps(dict(event=event, **data)), flush=True)


def save(name, value):
    with checked(ATTEMPT / name).open('x') as handle:
        json.dump(value, handle, indent=2)


checked(ROOT).mkdir(parents=True, exist_ok=True)
guard = (ROOT / 'recovery.lock').open('a')
fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
ATTEMPT = ROOT / (stamp + '_' + str(os.getpid()))
ATTEMPT.mkdir()
report = dict(utc=stamp, evidence_dir=str(ATTEMPT), conditions_changed=False, new_submission_command=False)

try:
    checked(REPO); checked(REPO / '.git'); checked(STAGING); checked(PUSHLOCK)
    report['active_processes'] = active_processes()
    if report['active_processes']:
        raise RuntimeError('A receiver or shared-repository Git process already exists; no restart performed.')
    branch = git('symbolic-ref', '--short', 'HEAD').stdout.decode().strip()
    if branch != 'hpc-mailbox':
        raise RuntimeError('Unexpected original repository branch: ' + branch)
    head = git('rev-parse', 'HEAD').stdout.decode().strip()
    target = git('rev-parse', 'refs/remotes/origin/hpc-mailbox').stdout.decode().strip()
    report.update(original_head=head, target_head=target)
    # The calling shell fetches metadata first, without changing the checkout.
    if git('merge-base', '--is-ancestor', head, target, required=False).returncode:
        raise RuntimeError('Original checkout has unpushed/divergent history; preserve it for review.')
    source = git('show', target + ':runner2.sh').stdout
    if hashlib.sha256(source).hexdigest() != SOURCE_SHA:
        raise RuntimeError('Original shared receiver source differs from reviewed bytes.')
    if hashlib.sha256(checked(REPO / 'runner2.sh').read_bytes()).hexdigest() != SOURCE_SHA:
        raise RuntimeError('Local shared receiver has a different version; no automatic replacement.')
    own_seq = git('show', target + ':inbox/' + OWN_CHANNEL + '/seq').stdout.strip()
    own_cmd = git('show', target + ':inbox/' + OWN_CHANNEL + '/cmd.sh').stdout
    if own_seq != b'29' or hashlib.sha256(own_cmd).hexdigest() != OWN_COMMAND_SHA:
        raise RuntimeError('Original training command/sequence changed; inspect before restart.')
    report['tracked_logs'] = git('ls-files', 'runner.log', 'runner2.log').stdout.decode().splitlines()
    dirty = git('diff', '--name-only', 'HEAD', '--').stdout.decode().splitlines()
    report['tracked_modifications'] = dirty
    if any(x not in ('runner.log', 'runner2.log') for x in dirty):
        raise RuntimeError('Tracked working changes outside logs require review; nothing reset.')
    for path in (REPO / 'runner.log', REPO / 'runner2.log', REPO / 'runner2.sh', HOME_DIR / '.hpc_runner_active.sh'):
        checked(path)
        if path.is_file():
            shutil.copy2(path, ATTEMPT / path.name)
    queue = run(['squeue', '-u', 'sunyiq', '-h', '-o', '%i|%j|%T|%M|%R'], timeout=30, required=False)
    report['queue_before'] = queue.stdout.decode(errors='replace').splitlines()
    report['queue_query_rc'] = queue.returncode
    pending, ambiguous = [], []
    entries = git('ls-tree', target + ':inbox').stdout.decode().splitlines()
    channels = [x.split('\t', 1)[1] for x in entries if x.split()[1] == 'tree']
    channels.append('default')
    for channel in channels:
        if not re.fullmatch(r'[A-Za-z0-9_.-]+', channel):
            raise RuntimeError('Unexpected channel name')
        prefix = 'inbox' if channel == 'default' else 'inbox/' + channel
        sequence = git('show', target + ':' + prefix + '/seq', required=False)
        if sequence.returncode:
            continue
        seq = sequence.stdout.strip().decode()
        if not seq.isdigit():
            raise RuntimeError('Invalid sequence for ' + channel)
        relative = 'outbox/' + channel + '/result_' + seq + '.txt'
        returned = git('cat-file', '-e', target + ':' + relative, required=False).returncode == 0
        if channel == 'default':
            returned = returned or git('cat-file', '-e', target + ':outbox/result_' + seq + '.txt', required=False).returncode == 0
        if returned:
            continue
        path = checked(STAGING / channel / ('result_' + seq + '.txt'))
        item = dict(channel=channel, sequence=int(seq), stage_exists=path.exists())
        if path.is_file():
            info = path.stat()
            with path.open('rb') as handle:
                header = handle.read(512)
                handle.seek(max(0, info.st_size - 8192))
                tail = handle.read()
            item.update(bytes=info.st_size, mtime_ns=info.st_mtime_ns,
                        header_matches=('### channel=' + channel + ' seq=' + seq).encode() in header,
                        complete=bool(re.search(rb'(?m)^### exit_code=\d+\r?$', tail)) and b'### finished=' in tail)
            if not item['header_matches'] or not item['complete']:
                ambiguous.append(item)
            else:
                item['action'] = 'Original receiver pushes existing receipt only; no command rerun.'
        elif path.exists() or checked(REPO / relative).exists():
            item['action'] = 'Ambiguous stage or local-only receipt; stop for review.'
            ambiguous.append(item)
        else:
            item['action'] = 'Original sequence remains pending; no staged result or local-only receipt.'
        pending.append(item)
    report.update(pending_channels=pending, ambiguous=ambiguous)
    save('preflight.json', report)
    emit('ORIGINAL_RECEIVER_PREFLIGHT', evidence_dir=str(ATTEMPT), pending=pending,
         active_processes=report['active_processes'], tracked_logs=report['tracked_logs'])
    if ambiguous:
        raise RuntimeError('Incomplete/ambiguous saved receipt found. Preserved evidence; no shared receiver started.')
    if '--restore' not in sys.argv:
        emit('INSPECT_ONLY_COMPLETE'); raise SystemExit(0)
    run(['git', '-c', 'gc.auto=0', 'merge', '--ff-only', target], timeout=120)
    if hashlib.sha256(checked(REPO / 'runner2.sh').read_bytes()).hexdigest() != SOURCE_SHA:
        raise RuntimeError('Receiver bytes changed during fast-forward.')
    live = active_processes()
    if live:
        raise RuntimeError('A receiver appeared during recovery; no second receiver launched: ' + repr(live))
    if PUSHLOCK.exists():
        if not PUSHLOCK.is_dir() or PUSHLOCK.stat().st_uid != os.getuid():
            raise RuntimeError('Unexpected push lock ownership/type.')
        # Preserve the abandoned lock and its timestamps rather than deleting it.
        PUSHLOCK.rename(ATTEMPT / 'abandoned_pushlock')
    log_path = ATTEMPT / 'live_runner2.log'
    env = dict(os.environ, MAILBOX_DIR=str(REPO), STAGING=str(STAGING), LOCKDIR=str(PUSHLOCK), HPC_RUNNER_DETACHED='0')
    with log_path.open('ab') as log:
        child = subprocess.Popen(['nohup', 'bash', str(REPO / 'runner2.sh')], cwd=REPO,
                                 stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                                 env=env, start_new_session=True)
    identity = dict(pid=child.pid, log=str(log_path), repo=str(REPO), staging=str(STAGING),
                    source_sha256=SOURCE_SHA, all_original_channels=True,
                    command_sequences_unchanged=True, conditions_changed=False)
    save('started.json', identity)
    emit('ORIGINAL_SHARED_RECEIVER_STARTED', **identity)
    for second in range(20):
        if child.poll() is not None:
            raise RuntimeError('Original receiver exited: ' + str(child.returncode) + '; inspect ' + str(log_path))
        time.sleep(1)
    identity['process_start_ticks'] = Path('/proc/' + str(child.pid) + '/stat').read_text().split()[21]
    save('alive_after_20s.json', identity)
    with log_path.open('rb') as handle:
        handle.seek(max(0, log_path.stat().st_size - 6000))
        print(handle.read().decode(errors='replace'), flush=True)
    emit('RESTORE_CHECK_COMPLETE', pid=child.pid, training_started_not_yet_verified=True)
except Exception as error:
    report['error'] = type(error).__name__ + ': ' + str(error)
    save('stopped_or_failed.json', report)
    emit('RECOVERY_STOPPED_OR_FAILED', error=report['error'], evidence_dir=str(ATTEMPT))
    raise SystemExit(1)
