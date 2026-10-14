#!/usr/bin/env bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'PY'
import base64,datetime,hashlib,json,re,subprocess
from pathlib import Path
root=Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')
assert root.resolve()==root and (root/'OWNER').read_text().strip()=='hydrol85935_revision_20261008_001'
d=root/'control/receipt253_diagnostic_20261014_001'
assert not d.exists(),'Existing one-time diagnostic evidence; never replay'
d.mkdir()
channel='hydrol85935-revision-20261008-001'
staged=Path.home()/'.hpc_mailbox_staging'/channel/'result_253.txt'
body=staged.read_bytes() if staged.is_file() else None
complete=bool(body and body.startswith(('### channel='+channel+' seq=253\n').encode())
              and re.search(rb'\n### exit_code=-?\d+\n### finished=[^\n]+\n?$',body))
proof=dict(remote_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
           main_channel=channel,main_sequence=253,staging_path=str(staged),staging_exists=body is not None,
           staging_complete=complete,main_command_reexecuted=False,scientific_jobs_modified=False,
           shared_runner_modified=False,new_scientific_job_submission=False)
if body is not None:
    (d/'result_253_preserved.txt').write_bytes(body)
    proof.update(staging_bytes=len(body),staging_sha256=hashlib.sha256(body).hexdigest(),
                 receipt_base64=base64.b64encode(body).decode() if complete else None,
                 partial_tail=body[-2400:].decode('utf-8',errors='replace') if not complete else None)
processes=subprocess.run(['ps','-eo','pid,ppid,etimes,stat,args'],capture_output=True,text=True,timeout=20)
proof['own_transport_processes']=[line for line in processes.stdout.splitlines()
    if 'hpc_runner_active' in line or '/cmd_253.sh' in line]
runner_log=Path('/data1/home/sunyiq/hpc_mailbox/runner2.log')
if runner_log.is_file():
    with runner_log.open('rb') as f:
        f.seek(max(0,runner_log.stat().st_size-16000));tail=f.read().decode('utf-8',errors='replace')
    proof['runner_own_channel_tail']=[line for line in tail.splitlines() if channel in line][-12:]
    proof['runner_log_bytes']=runner_log.stat().st_size
    proof['runner_log_mtime']=runner_log.stat().st_mtime
with (d/'diagnostic.json').open('x') as f:json.dump(proof,f,indent=2)
print('RECEIPT253_DIAGNOSTIC '+json.dumps(proof),flush=True)

PY
