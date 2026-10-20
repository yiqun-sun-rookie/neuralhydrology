"""Move only this unstarted pending job to local; running work is preserved."""
import json
import re
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path("/data1/home/sunyiq/regge_experiments/REGGE-PQX01-FROZEN-QE-CROSSBANK/20261020-v01")
JOB = "245625"
events = []


def call(args):
    result = subprocess.run(args, capture_output=True, text=True)
    events.append(dict(command=args, returncode=result.returncode,
                       stdout=result.stdout, stderr=result.stderr))
    return result


def inspect():
    result = call(["scontrol", "show", "job", JOB])
    if result.returncode:
        return None, result.stdout
    value = result.stdout
    assert "JobId=" + JOB + " " in value and "JobName=regge_pqx01" in value
    assert "Command=" + str(ROOT / "job.slurm") in value
    assert "WorkDir=" + str(ROOT) in value
    return re.search(r"\bJobState=(\S+)", value).group(1), value


def finish(decision, state):
    value = dict(utc=datetime.now(timezone.utc).isoformat(), job_id=int(JOB),
        decision=decision, final_state=state, events=events,
        authorization="User 2026-10-20 allows local or HPC, cost not limiting",
        scope="only this experiment; no other jobs or shared runner changed")
    path = ROOT / "receipts" / ("resource_route_" + str(time.time_ns()) + ".json")
    with path.open("x") as f:
        json.dump(value, f, indent=2)
    print(json.dumps(value, indent=2), flush=True)


receipt = json.loads((ROOT / "receipts/submission_receipt.json").read_text())
assert str(receipt["job_id"]) == JOB
state, detail = inspect()
if state != "PENDING":
    call(["sacct", "-j", JOB, "--format=JobID,JobName,State,ExitCode,ElapsedRaw,NodeList", "-P"])
    finish("KEEP_HPC_NO_LOCAL_LAUNCH", state)
elif any((ROOT / "receipts" / name).exists() for name in
         ["preflight.json", "execution_started.json", "bridge_FULL_0_identity.json", "bridge_W_0_identity.json"]):
    finish("KEEP_HPC_EXISTING_EXECUTION_EVIDENCE", state)
else:
    hold = call(["scontrol", "hold", JOB])
    state, detail = inspect()
    if hold.returncode or state != "PENDING" or "Priority=0 " not in detail:
        if hold.returncode == 0:
            call(["scontrol", "release", JOB])
        finish("KEEP_HPC_HOLD_NOT_CONFIRMED", state)
    else:
        cancellation = call(["scancel", JOB])
        state, detail = inspect()
        for _ in range(5):
            if state == "CANCELLED":
                break
            time.sleep(1)
            state, detail = inspect()
        history = call(["sacct", "-j", JOB, "--format=JobID,JobName,State,ExitCode,ElapsedRaw,NodeList", "-P"])
        confirmed = state == "CANCELLED" or re.search(
            r"^245625\|regge_pqx01\|CANCELLED(?: by [0-9]+)?\|", history.stdout, re.M)
        finish("LOCAL_RELEASED_PENDING_JOB_CANCELLED" if cancellation.returncode == 0 and confirmed
               else "CANCELLATION_UNCONFIRMED_NO_LOCAL_LAUNCH", state)
