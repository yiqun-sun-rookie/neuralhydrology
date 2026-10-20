"""Read only this experiment and its mailbox staging; never submit or cancel."""
import base64
import datetime
import hashlib
import json
import subprocess
from pathlib import Path
import psutil

ROOT = Path("/data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/state_channel_step3_replay_20261020_002")
CHANNEL = "knet-state-step3-20261020-002"
value = dict(utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
             root=str(ROOT), exists=ROOT.exists(), files={}, processes=[])
for path in [Path.home()/".hpc_mailbox_staging"/CHANNEL/"result_2.txt",
             ROOT/"deployment_owner.json", ROOT/"submission_started.json",
             ROOT/"submission_reply.json", ROOT/"execution_identity.json",
             ROOT/"runs/02092500/attempt_001/controller_started.json",
             ROOT/"runs/02092500/attempt_001/startup_handshake.json",
             ROOT/"runs/02092500/attempt_001/receipt.json",
             ROOT/"runs/02092500/attempt_001/result.json",
             ROOT/"runs/02092500/attempt_001/recovery_gate.json",
             ROOT/"logs/bootstrap_handshake.json",
             ROOT/"logs/bootstrap_failure.json"]:
    if path.is_file():
        raw = path.read_bytes()
        assert len(raw) < 100000
        value["files"][str(path)] = dict(bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest(),
                                       content_base64=base64.b64encode(raw).decode())
for proc in psutil.process_iter(["pid", "ppid", "name", "cmdline", "create_time"]):
    try:
        line = " ".join(proc.info["cmdline"] or [])
        if CHANNEL in line or str(ROOT) in line:
            value["processes"].append({k:proc.info[k] for k in ["pid", "ppid", "name", "create_time"]})
    except (psutil.AccessDenied, psutil.NoSuchProcess):
        pass
path = ROOT/"execution_identity.json"
if path.is_file():
    identity = json.loads(path.read_bytes())
    job = identity.get("job_id")
    if job:
        for name, args in [("squeue", ["squeue", "-j", job, "-h", "-o", "%i|%T|%M|%R"]),
                           ("sacct", ["sacct", "-j", job, "-n", "-P", "-o", "JobID,State,ExitCode,ElapsedRaw,NodeList"])]:
            p = subprocess.run(args, capture_output=True, text=True, timeout=15)
            value[name] = dict(returncode=p.returncode, stdout=p.stdout, stderr=p.stderr)
print("OWN_DEPLOYMENT_DIAGNOSIS="+json.dumps(value), flush=True)
