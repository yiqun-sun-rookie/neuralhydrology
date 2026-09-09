"""C-only adapter around the byte-preserved once-only A/B launcher."""
from pathlib import Path

import launch_once as frozen_guard
from evidence_contract import REMOTE, file_hash, read_json, require
from stage_c import combos_from_lock, validate_c_combo


def configure_guard(root):
    root = Path(root)
    require(root == Path(REMOTE) / "stages/C", "Exact C root required")
    lock = read_json(root / "TOP_THREE_LOCK.json")
    rows = combos_from_lock(lock)
    manifest = read_json(root / "STAGE_C_MANIFEST.json")
    require(manifest.get("top_three_lock_sha256") == file_hash(root / "TOP_THREE_LOCK.json"), "C lock differs from manifest")

    def make(stage):
        require(stage == "C", "C adapter cannot launch A/B")
        return rows

    def index(stage, value):
        make(stage)
        require(type(value) is int and 0 <= value < 15, "Invalid C index")
        return value

    def combo(stage, value, row):
        index(stage, value)
        return validate_c_combo(lock, value, row)

    # Bind only orchestration inputs in this C-only process; numerical launcher,
    # source/data checks, runtime check, claim and seeding functions are unchanged.
    frozen_guard.REMOTE_STAGE_ROOTS = {"C": root}
    frozen_guard.make_combos = make
    frozen_guard.validate_index = index
    frozen_guard.validate_combo = combo
    return frozen_guard


if __name__ == "__main__":
    configure_guard(Path(__file__).resolve().parent).main()
