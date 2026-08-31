from __future__ import annotations

from hashlib import sha256
import json
from pathlib import Path
import re
import tarfile


CHANNEL_ROOT = Path(__file__).resolve().parent
MAILBOX_ROOT = CHANNEL_ROOT.parents[1]
CONTROLLER = CHANNEL_ROOT / "seq91_a39_submit_formal_evaluation_eval3.sh"
PAYLOAD_ROOT = (
    MAILBOX_ROOT
    / "payload"
    / "kalmannet-daily-camels"
    / "a39_epoch75_single_basin_formal_evaluation_eval3_seq91_20260831"
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
    19_742,
    "079c2353f319f05e0d3737630752a705067126e1abfa5d99b82f29fb2b5162c7",
)
assert identity(ARCHIVE) == (
    228_450,
    "bc4119187c70183dd90d599f7871e2e8033b4005c6be06b5a2ce4a5b74addca6",
)
assert identity(OUTER_MANIFEST) == (
    2_627,
    "ea825788518b5df9cf6335e20453210740a1e23f54d15eef608128a2641421c3",
)

controller = CONTROLLER.read_text(encoding="utf-8")
required = (
    "DAILY_CAMELS_KNET_EPOCH75_SINGLE_BASIN_FORMAL_EVALUATION_A39_A800_EVAL3_SEQ91",
    "/data1/home/sunyiq/kalmannet_daily_camels_knet_a39_formal_evaluation3_20260831",
    "source_A39_formal_evaluation_seq91",
    "8d835ff7cb2dae05c55c0ec4d7769761353bffe619e74490e6b0f72c2140da26",
    "dacc0fb4c28ac48942f892df3015b7f92f0b2c9df9e04cf387534d55ac93d74d",
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
assert len(members) == 39
assert all(member.isfile() and not member.issym() and not member.islnk() for member in members)
names = [member.name for member in members]
assert not any(name.endswith(".pt") for name in names)
assert not any("/evaluation/" in name and name.endswith(".npz") for name in names)
assert not any("RECONSTRUCT_SEQ89.tar.gz" in name for name in names)
assert not any(name.endswith("member_identity_verification.json") for name in names)

print("SEQ91_A39_STATIC_CHECK_PASS")
