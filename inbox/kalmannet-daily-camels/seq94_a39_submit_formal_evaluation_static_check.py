from __future__ import annotations

from hashlib import sha256
import json
from pathlib import Path
import re
import tarfile


CHANNEL_ROOT = Path(__file__).resolve().parent
MAILBOX_ROOT = CHANNEL_ROOT.parents[1]
CONTROLLER = CHANNEL_ROOT / "seq94_a39_submit_formal_evaluation_eval4.sh"
PAYLOAD_ROOT = (
    MAILBOX_ROOT
    / "payload"
    / "kalmannet-daily-camels"
    / "a39_epoch75_single_basin_formal_evaluation_eval4_seq94_20260831"
)
ARCHIVE = PAYLOAD_ROOT / (
    "DAILY_CAMELS_KNET_EPOCH75_SINGLE_BASIN_FORMAL_EVALUATION_V1_20260831_A39.tar.gz"
)
OUTER_MANIFEST = PAYLOAD_ROOT / "bundle_manifest.sha256.json"


def identity(path: Path) -> tuple[int, str]:
    if not path.is_file() or path.is_symlink():
        raise AssertionError(f"absent, non-regular, or symbolic: {path}")
    content = path.read_bytes()
    return len(content), sha256(content).hexdigest()


assert identity(CONTROLLER) == (
    24_112,
    "051fe22b834399e7e22a056448309d49454461cdc4e206be4b76b4a6652bec73",
)
assert identity(ARCHIVE) == (
    229_971,
    "d427c9aca30e26b0f51f722c6ff67763e15e8be5398e744f54e6828193c223bb",
)
assert identity(OUTER_MANIFEST) == (
    2_627,
    "9678376298f9d91addc3cf98dfac0b212142e61b6dbd45e55a1a699578e5f0e8",
)

controller = CONTROLLER.read_text(encoding="utf-8")
required = (
    "DAILY_CAMELS_KNET_EPOCH75_SINGLE_BASIN_FORMAL_EVALUATION_A39_A800_EVAL4_SEQ94",
    "/data1/home/sunyiq/kalmannet_daily_camels_knet_a39_formal_evaluation4_20260831",
    "source_A39_formal_evaluation_seq94",
    "00ae298e699c5ea81bbb0cc25886f94d30fc8e32a1f23c30202d88f3a5a1bb3f",
    "dacc0fb4c28ac48942f892df3015b7f92f0b2c9df9e04cf387534d55ac93d74d",
    "8a6790e87027a45160a21a9c3cc45a009702e88785da49dcaf6c624ffdd3fb38",
    "f15f30f8587be56c69c0f76fb7f6b77f5c9b2a9963d6d6a5fd46fbb4d71b5c4e",
    "8270074aacfa7bef826cd47ada87e352a4bb44529fdefbed19dcb3b080d2d1a5",
    "DAILY_CAMELS_KNET_EPOCH75_SINGLE_BASIN_FORMAL_EVALUATION_A39_A800_EVAL3_SEQ91",
    "216847|daily-knet-a39-s91|sunyiq|hgpu8|FAILED|2:0|00:00:04|",
    "A39 formal-evaluation preflight failed: allocation must contain exactly one GPU",
    "89975d9d69d477d625ae11713a96edf618cb6189284e280f3008bfe0f785676d",
    "ac2fc24c15edb7b9d5e22ced035141c4fa256e79f8067ea9225be9613abe8f56",
    "A39_A38_TERMINAL_EVIDENCE=${RECONSTRUCTED_RUNTIME}",
    "A39_A38_RECONSTRUCTION_RECEIPT=${RECEIPT_RUNTIME}",
)
for value in required:
    assert value in controller, value

assert len(re.findall(r"^\s*sbatch --parsable", controller, flags=re.MULTILINE)) == 1
for forbidden in ("scancel", "scontrol update", " kill ", "pkill", "requeue"):
    assert forbidden not in controller
assert '"state": "PREPARED"' in controller
assert "os.fsync(handle.fileno())" in controller
assert "recover_only" in controller
assert "no sbatch retry permitted" in controller
assert 'RESULT91="${MAILBOX_ROOT}/outbox/${CHANNEL}/result_91.txt"' in controller
assert 'RESULT92="${MAILBOX_ROOT}/outbox/${CHANNEL}/result_92.txt"' in controller
assert 'RESULT93="${MAILBOX_ROOT}/outbox/${CHANNEL}/result_93.txt"' in controller
assert '"eval3_submission_result91_sha256": result91_sha' in controller
assert '"eval3_terminal_result92_sha256": result92_sha' in controller
assert '"eval3_diagnostic_result93_sha256": result93_sha' in controller
assert '"prior_failed_job_id": "216847"' in controller
assert (
    '"prior_failure_class": '
    '"recoverable_preflight_gpu_count_field_misinterpretation"'
) in controller
assert controller.count("require_file \"${RESULT91}\"") == 1
assert controller.count("require_file \"${RESULT92}\"") == 1
assert controller.count("require_file \"${RESULT93}\"") == 1
assert "SEQ91_A39_STATIC_CHECK_PASS" in controller
assert "SEQ91_A39_DISPATCH_VERIFIED" in controller
assert "SEQ92_A39_STATUS_QUERY_COMPLETE job_id=216847 squeue_exit=1 sacct_exit=0" in controller
assert "51974b51ca8d9a4dcaf354cf680166580528b84e573d3e60b06b44418e034ade" in controller
assert "squeue -h" in controller and "sacct -n -X" in controller
assert "active_a39_ids" in controller
assert controller.index("cp --reflink=auto") < controller.index('mkdir "${LOCK_ROOT}"')
assert controller.index('mkdir "${LOCK_ROOT}"') < controller.index("sbatch --parsable")
assert "member_count=33 reserved_member_count=0" in controller
assert "member_content_identity_verified=true" in controller
assert "evaluation_array_reads=0 formal_evaluation_outputs_created=0" in controller
assert "/hpc_mailbox/outbox/kalmannet-daily-camels/DAILY_CAMELS_KNET_A38_JOB215801_TERMINAL_EVIDENCE_SEQ82.tar.gz" not in controller

outer = json.loads(OUTER_MANIFEST.read_text(encoding="utf-8"))
assert outer["archive_sha256"] == identity(ARCHIVE)[1]
assert outer["archive_size"] == identity(ARCHIVE)[0]
assert outer["member_count"] == 38
assert outer["checkpoint_member_count"] == 0
assert outer["historical_evaluation_array_member_count"] == 0
external = outer["external_artifacts"]
assert external["a38_original_terminal_evidence_identity"]["sha256"] == (
    "72feda409ea3490ccd9a289b1313c9beb276c1cc267a15111dc19e63d5815317"
)
assert external["a38_reconstructed_terminal_evidence_archive"]["sha256"] == (
    "89975d9d69d477d625ae11713a96edf618cb6189284e280f3008bfe0f785676d"
)
assert external["a38_member_identity_receipt"]["sha256"] == (
    "ac2fc24c15edb7b9d5e22ced035141c4fa256e79f8067ea9225be9613abe8f56"
)

with tarfile.open(ARCHIVE, mode="r:gz") as archive:
    members = archive.getmembers()
    by_name = {member.name: archive.extractfile(member).read() for member in members}
assert len(members) == 39
assert all(member.isfile() and not member.issym() and not member.islnk() for member in members)
names = [member.name for member in members]
assert not any(name.endswith(".pt") for name in names)
assert not any("/evaluation/" in name and name.endswith(".npz") for name in names)
assert not any("RECONSTRUCT_SEQ89.tar.gz" in name for name in names)
assert not any(name.endswith("member_identity_verification.json") for name in names)

slurm_text = by_name[
    "hpc/daily_camels_knet_formal_evaluation/submit_evaluation_gpu.slurm"
].decode("utf-8")
preflight_text = by_name[
    "hpc/daily_camels_knet_formal_evaluation/preflight.py"
].decode("utf-8")
evaluation_text = by_name[
    "scripts/run_daily_camels_knet_epoch75_formal_evaluation.py"
].decode("utf-8")
assert "#SBATCH --gres=gpu:1" in slurm_text
assert '"fixed_slurm_request": "--gres=gpu:1"' in preflight_text
assert '"slurm_gpus_on_node_required": False' in preflight_text
assert "parsed_slurm_gpu_count is not None and parsed_slurm_gpu_count != 1" in preflight_text
assert 'or "," in visible_device' in preflight_text
assert "GPU query did not return exactly one device" in preflight_text
assert "int(torch.cuda.device_count()) != 1" in evaluation_text
assert 'torch.cuda.get_device_name(0)) != "NVIDIA A800-SXM4-80GB"' in evaluation_text

print("SEQ94_A39_STATIC_CHECK_PASS")
