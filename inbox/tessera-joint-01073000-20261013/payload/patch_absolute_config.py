"""Repair only the queued pilot's config-path logging; retain original bytes."""
import hashlib
import json
from pathlib import Path

root = Path("/data1/home/sunyiq/tessera_joint_01073000_20261013_001").resolve()
if root.as_posix() != "/data1/home/sunyiq/tessera_joint_01073000_20261013_001" or (root / "job_id.txt").read_text() != "241691":
    raise ValueError("Unexpected experiment root or job")
relative = "src/tessera_joint/scripts/train_temporal_pilot.py"
target = root / relative
payload = Path.home() / "hpc_mailbox/inbox/tessera-joint-01073000-20261013/payload/train_temporal_pilot_v1_1.py"
old_hash = "8903e2b728487a18c2ee7c6c1fa55bac4dccfdaf1a8d4addf55a8fc3c660cbd5"
new_hash = "5fb5b6592bcdf86dc3ef050d4296a2010adaeff81a7b912941f0b0ffcb6c3eef"
before, after = target.read_bytes(), payload.read_bytes()
if hashlib.sha256(after).hexdigest() != new_hash:
    raise ValueError("Patch payload mismatch")
current = hashlib.sha256(before).hexdigest()
if current == new_hash:
    print("ABSOLUTE_CONFIG_FIX_ALREADY_PRESENT")
elif current == old_hash:
    marker = b"    args = parser.parse_args()\n"
    if before.replace(marker, marker + b"    args.config = args.config.resolve()\n", 1) != after:
        raise ValueError("Patch is broader than a path normalization")
    manifest_path = root / "MANIFEST.sha256"
    manifest = manifest_path.read_bytes()
    old_line = (old_hash + "  " + relative).encode()
    new_line = (new_hash + "  " + relative).encode()
    if manifest.count(old_line) != 1:
        raise ValueError("Original manifest binding not found")
    with target.with_suffix(".py.v1_original").open("xb") as handle:
        handle.write(before)
    with (root / "MANIFEST.v1_original.sha256").open("xb") as handle:
        handle.write(manifest)
    target.write_bytes(after)
    manifest_path.write_bytes(manifest.replace(old_line, new_line, 1))
    (root / "launch_path_fix.json").write_text(json.dumps({"before": old_hash, "after": new_hash,
        "change": "Resolve config CLI path before relative-to-root provenance logging; no model, data or training change",
        "local_result": "Original frozen driver completed locally with an absolute config CLI argument"}, indent=2))
    print("ABSOLUTE_CONFIG_FIX_APPLIED")
else:
    raise ValueError("Unexpected driver hash; no overwrite performed")
