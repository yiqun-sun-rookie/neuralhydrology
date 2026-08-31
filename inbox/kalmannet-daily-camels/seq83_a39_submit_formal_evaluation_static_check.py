from pathlib import Path
import re


root = Path(__file__).resolve().parent
controller = (root / "seq83_a39_submit_formal_evaluation.sh").read_text(encoding="utf-8")
dispatcher = (root / "cmd.sh").read_text(encoding="utf-8")

required_identities = {
    "archive": "7d103b0fc096dd841c42f809f0c02b23e0cfa5733dab15242ce68c6ea7a60a47",
    "outer_manifest": "7a7e272bf8a3febf9fcb6484f13ab9c8643c7a3d5f905e4e0089fae3814b11ba",
    "slurm": "a72e4a3d7b72aa04d03822aac4dab766e02f09361928c15f53b48034fcdecb53",
    "submission_token": "df7bb91652823a495be3a45e1afc69cf192422ea25de20def3d19cea982d0f0e",
    "result82": "a16bfb72c526ff8ec15bb5940b80d4abe8aabe96ffda6bdd322ea604a4229e69",
}
for label, identity in required_identities.items():
    assert identity in controller or identity in dispatcher, label

assert controller.count("\nsbatch --parsable ") == 1
for forbidden in ("scancel", "scontrol update", " kill ", "pkill", "requeue"):
    assert forbidden not in controller
assert '"state": "PREPARED"' in controller
assert "os.fsync(handle.fileno())" in controller
assert "record_job_id" in controller
assert 'bound_path.open("x"' not in controller
assert "bound_path.open('x'" not in controller
assert "bound_written_by_controller=false" in controller
assert "recover_only" in controller
assert "no sbatch retry permitted" in controller
assert "squeue -h" in controller and "sacct -n -X" in controller
assert '--comment="$SUBMISSION_COMMENT"' in controller
assert '--chdir="$SOURCE_ROOT"' in controller
assert re.search(r'if \[\[ -e "\$LOCK_ROOT".*?recover_only', controller, re.S)
assert "initial-pre-sbatch" in controller
assert "final-pre-sbatch" in controller
assert "post-sbatch" in controller
assert "unique_before=true unique_after=true" in controller
assert "python -B -S - <<'PY'" in controller
assert "if len(members) != 39:" in controller
assert 'mkdir -p "$STATUS_ROOT/locks" "$RUN_ROOT/logs"' in controller
assert 'mkdir -p "$STATUS_ROOT/locks" "$RUN_ROOT/logs" "$RUN_ROOT/verification"' not in controller
assert '"$(tr -d \'[:space:]\' < "$SEQUENCE_FILE")" == "$EXPECTED_SEQUENCE"' in dispatcher
assert 'EXPECTED_SEQUENCE="83"' in dispatcher
assert "result_83.txt" in dispatcher
assert "815fa9232b496098a6f81de06856693a95a3960289e09766a1b8f8ee9f7eaa23" in dispatcher

print("SEQ83_A39_STATIC_CHECK_PASS")
