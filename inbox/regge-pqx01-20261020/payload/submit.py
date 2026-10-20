"""Login-node file deployment and scheduler submission only; no model calls."""
import argparse
import hashlib
import json
import os
import re
import subprocess
import tarfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path("/data1/home/sunyiq/regge_experiments/REGGE-PQX01-FROZEN-QE-CROSSBANK/20261020-v01")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value, exclusive=False):
    with path.open("x" if exclusive else "w", encoding="utf-8") as f:
        json.dump(value, f, indent=2)


def query(job):
    for cmd in [["squeue", "-j", str(job), "-o", "%.18i %.24j %.10T %.12M %.40R"],
                ["scontrol", "show", "job", str(job)],
                ["sacct", "-j", str(job), "--format=JobID,JobName,State,ExitCode,ElapsedRaw,NodeList", "-P"]]:
        result = subprocess.run(cmd, capture_output=True, text=True)
        print(result.stdout, result.stderr, flush=True)


def decrypt(archive, expected, plain_sha):
    assert archive.is_file() and sha(archive) == expected
    transfer = ROOT.with_name(ROOT.name + "-transfer")
    data = archive.read_bytes()
    assert data[:8] == b"RGEPQX01"
    size = int.from_bytes(data[8:10], "big")
    assert size == 256
    password = subprocess.run(["openssl", "pkeyutl", "-decrypt", "-inkey",
        str(transfer / "transfer_private.pem"), "-pkeyopt", "rsa_padding_mode:oaep"],
        input=data[10:10+size], capture_output=True, check=True).stdout
    assert len(password) == 64 and all(c in b"0123456789abcdef" for c in password)
    encrypted = transfer / (expected + ".aes")
    if not encrypted.exists():
        with encrypted.open("xb") as f:
            f.write(data[10+size:])
    else:
        assert encrypted.read_bytes() == data[10+size:]
    plain = transfer / (plain_sha + ".tar.gz")
    if not plain.exists():
        # Random 256-bit password is passed only through stdin, never argv or the mailbox.
        result = subprocess.run(["openssl", "enc", "-d", "-aes-256-cbc", "-md", "sha256",
            "-pass", "stdin", "-in", str(encrypted)], input=password+b"\n", capture_output=True, check=True)
        assert hashlib.sha256(result.stdout).hexdigest() == plain_sha
        with plain.open("xb") as f:
            f.write(result.stdout)
        os.chmod(plain, 0o600)
    assert sha(plain) == plain_sha
    return plain


def main(archive, expected, plain_sha):
    archive = decrypt(archive, expected, plain_sha)
    receipt = ROOT / "receipts/submission_receipt.json"
    marker = ROOT / "receipts/submission_started.json"
    if ROOT.exists():
        if receipt.exists():
            query(json.loads(receipt.read_text())["job_id"])
            return
        raise RuntimeError("Existing root without confirmed submission; reconcile started/stdout/sacct, never overwrite")
    ROOT.parent.mkdir(parents=True, exist_ok=True)
    ROOT.mkdir(exist_ok=False)
    with tarfile.open(archive, "r:gz") as tar:
        members = tar.getmembers()
        for member in members:
            assert member.isfile(), member.name
            target = (ROOT / member.name).resolve()
            assert target.is_relative_to(ROOT.resolve()), member.name
            assert not target.exists()
        tar.extractall(ROOT, members=members)
    for name in ["logs", "receipts", "outputs"]:
        (ROOT / name).mkdir(exist_ok=False)
    manifest = json.loads((ROOT / "payload_manifest.json").read_text())
    for name, expected_hash in manifest.items():
        assert sha(ROOT / name) == expected_hash, name
    assert b"\r" not in (ROOT / "job.slurm").read_bytes()
    script = (ROOT / "job.slurm").read_text()
    assert "--mem" not in script and "--gres" not in script
    queue = subprocess.run(["squeue", "-u", "sunyiq", "-o", "%.18i %.24j %.10T %.40R"],
                           capture_output=True, text=True, check=True)
    (ROOT / "receipts/existing_jobs_before.txt").write_text(queue.stdout)
    assert "regge_pqx01" not in queue.stdout, "Same-name active job requires reconciliation"
    started = {"utc": datetime.now(timezone.utc).isoformat(), "command": ["sbatch", str(ROOT / "job.slurm")],
               "script_sha256": sha(ROOT / "job.slurm"), "payload_sha256": plain_sha,
               "encrypted_payload_sha256": expected,
               "root": str(ROOT), "status": "submission_started"}
    write(marker, started, exclusive=True)
    # A repeat invocation is stopped by the root/marker even if interrupted during this call.
    result = subprocess.run(started["command"], cwd=ROOT, capture_output=True, text=True)
    output = result.stdout + result.stderr
    (ROOT / "receipts/submission_stdout.txt").write_text(output)
    print(output, flush=True)
    matches = re.findall(r"Submitted batch job ([0-9]+)", output)
    assert result.returncode == 0 and len(matches) == 1, "Submission outcome must be reconciled"
    job = int(matches[0])
    write(receipt, dict(started, status="submitted", job_id=job,
                       returncode=result.returncode), exclusive=True)
    query(job)


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--archive", type=Path, required=True)
    p.add_argument("--sha256", required=True)
    p.add_argument("--plain-sha256", required=True)
    a = p.parse_args()
    main(a.archive, a.sha256, a.plain_sha256)
