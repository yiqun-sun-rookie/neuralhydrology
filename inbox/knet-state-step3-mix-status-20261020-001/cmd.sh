#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -u -B - <<'PY'
import os,json,hashlib,re,datetime,socket
from pathlib import Path
import psutil
channel='knet-state-step3-mix-20261020-001'
root=Path('/data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/state_channel_step3_mix_20261020_001')
files={}
for path in [Path.home()/'.hpc_mailbox_staging'/channel/'cmd_3.sh',
             Path.home()/'.hpc_mailbox_staging'/channel/'result_3.txt',
             Path.home()/'hpc_mailbox/outbox'/channel/'result_3.txt',
             root/'transport_archive/index.json',root/'transport_archive/archive.tar.gz']:
    item=dict(exists=path.exists())
    if path.is_file():
        item.update(size=path.stat().st_size,mtime=path.stat().st_mtime)
        if path.suffix in ('.json','.sh') or path.name=='result_3.txt':
            raw=path.read_bytes()
            item['sha256']=hashlib.sha256(raw).hexdigest()
            if path.name=='result_3.txt':
                text=raw.decode(errors='replace')
                item.update(exit_markers=re.findall(r'^### exit_code=.*$',text,re.M),
                            finished_markers=re.findall(r'^### finished=.*$',text,re.M),
                            tail=text[-1200:])
            elif path.name=='index.json':item['index']=json.loads(raw)
    files[str(path)]=item
processes=[]
for p in psutil.process_iter(['pid','ppid','name','uids','cmdline','create_time','status']):
    try:
        x=p.info
        if x['uids'].real!=os.getuid():continue
        command=' '.join(x['cmdline'] or [])
        own=channel in command or str(root) in command
        if own or (x['name'] or '').startswith('git'):
            processes.append(dict(pid=x['pid'],ppid=x['ppid'],name=x['name'],status=x['status'],
                                  age_seconds=max(0,datetime.datetime.now().timestamp()-x['create_time']),
                                  matches_own_command=own))
    except (psutil.NoSuchProcess,psutil.AccessDenied):pass
print('TRANSPORT_DIAGNOSIS='+json.dumps(dict(host=socket.gethostname(),
    utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),files=files,processes=processes[:100],
    scientific_jobs_submitted=0,receiver_changed=False)),flush=True)
PY
