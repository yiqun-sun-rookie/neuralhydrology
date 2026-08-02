import json
import os
from pathlib import Path
import stat
import sys
import threading
from concurrent.futures import ThreadPoolExecutor
from types import SimpleNamespace

import numpy as np
import pytest


IDEA_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IDEA_ROOT))


def test_hashes_are_deterministic_and_array_hash_is_payload_only(tmp_path):
    from artifact_v09 import array_payload_sha256, canonical_sha256, sha256_file

    path = tmp_path / "value.bin"
    path.write_bytes(b"abc")
    assert sha256_file(path) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    assert canonical_sha256({"b": 2, "a": 1}) == canonical_sha256({"a": 1, "b": 2})

    array = np.arange(12, dtype=np.float32).reshape(3, 4)
    assert array_payload_sha256(array) == array_payload_sha256(array.copy())
    with pytest.raises(ValueError, match="C-contiguous"):
        array_payload_sha256(array[:, ::2])


def test_atomic_json_refuses_overwrite_and_nonfinite_values(tmp_path):
    from artifact_v09 import write_json_atomic

    path = tmp_path / "value.json"
    write_json_atomic(path, {"status": "complete", "number": 1})
    assert json.loads(path.read_text(encoding="utf-8"))["status"] == "complete"
    assert [item for item in tmp_path.iterdir() if item.suffix == ".tmp"] == []
    with pytest.raises(FileExistsError):
        write_json_atomic(path, {"status": "replacement"})
    with pytest.raises(ValueError):
        write_json_atomic(tmp_path / "bad.json", {"value": float("nan")})


def test_atomic_json_does_not_overwrite_a_racing_destination(tmp_path, monkeypatch):
    import os

    from artifact_v09 import write_json_atomic

    path = tmp_path / "race.json"
    real_link = os.link

    def racing_link(source, destination):
        Path(destination).write_text('{"owner":"other"}\n', encoding="utf-8")
        return real_link(source, destination)

    monkeypatch.setattr(os, "link", racing_link)
    with pytest.raises(FileExistsError):
        write_json_atomic(path, {"owner": "builder"})
    assert json.loads(path.read_text(encoding="utf-8")) == {"owner": "other"}
    assert [item for item in tmp_path.iterdir() if item.suffix == ".tmp"] == []


def test_two_atomic_json_writers_use_distinct_temporaries(tmp_path, monkeypatch):
    import os

    from artifact_v09 import write_json_atomic

    path = tmp_path / "concurrent.json"
    barrier = threading.Barrier(2)
    real_link = os.link

    def synchronized_link(source, destination):
        barrier.wait(timeout=5)
        return real_link(source, destination)

    monkeypatch.setattr(os, "link", synchronized_link)

    def write(value):
        try:
            write_json_atomic(path, {"value": value})
            return "created"
        except FileExistsError:
            return "lost_race"

    with ThreadPoolExecutor(max_workers=2) as pool:
        outcomes = sorted(pool.map(write, (1, 2)))
    assert outcomes == ["created", "lost_race"]
    assert json.loads(path.read_text(encoding="utf-8"))["value"] in (1, 2)
    assert [item for item in tmp_path.iterdir() if item.suffix == ".tmp"] == []


def test_exact_inventory_and_directory_promotion_are_fail_closed(tmp_path):
    from artifact_v09 import exact_file_inventory, promote_directory

    building = tmp_path / "attempt.building"
    building.mkdir()
    (building / "a.txt").write_text("a", encoding="utf-8")
    (building / "b.txt").write_text("b", encoding="utf-8")
    inventory = exact_file_inventory(building, ("a.txt", "b.txt"))
    assert [item["relative_path"] for item in inventory] == ["a.txt", "b.txt"]
    (building / "extra.txt").write_text("x", encoding="utf-8")
    with pytest.raises(ValueError, match="inventory"):
        exact_file_inventory(building, ("a.txt", "b.txt"))
    (building / "extra.txt").unlink()

    final = tmp_path / "attempt"
    promote_directory(building, final)
    assert final.is_dir() and not building.exists()
    other = tmp_path / "other.building"
    other.mkdir()
    with pytest.raises(FileExistsError):
        promote_directory(other, final)


def test_reparse_detection_uses_lstat_for_a_broken_windows_junction(tmp_path, monkeypatch):
    import artifact_v09 as module

    path = tmp_path / "broken-junction"
    reparse_flag = int(getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400))
    monkeypatch.setattr(
        os,
        "lstat",
        lambda candidate: SimpleNamespace(st_mode=0, st_file_attributes=reparse_flag),
    )
    assert module.is_reparse_point(path) is True


def test_directory_promotion_rejects_reparse_building_and_final_paths(tmp_path, monkeypatch):
    import artifact_v09 as module

    building = tmp_path / "attempt.building"
    building.mkdir()
    final = tmp_path / "attempt"
    real_is_reparse = module.is_reparse_point

    monkeypatch.setattr(
        module,
        "is_reparse_point",
        lambda candidate: Path(candidate) == building or real_is_reparse(candidate),
    )
    with pytest.raises(ValueError, match="reparse"):
        module.promote_directory(building, final)

    monkeypatch.setattr(
        module,
        "is_reparse_point",
        lambda candidate: Path(candidate) == final or real_is_reparse(candidate),
    )
    with pytest.raises(ValueError, match="reparse"):
        module.promote_directory(building, final)


def test_trusted_path_rejects_reparse_ancestor_above_root(tmp_path, monkeypatch):
    import artifact_v09 as module

    marked_ancestor = tmp_path.parent
    original = module.is_reparse_point
    monkeypatch.setattr(
        module,
        "is_reparse_point",
        lambda path: Path(path) == marked_ancestor or original(path),
    )
    with pytest.raises(ValueError, match="above trusted root"):
        module.assert_no_reparse_components(tmp_path, tmp_path / "payload.json")


def test_source_tree_manifest_binds_paths_and_bytes(tmp_path):
    from artifact_v09 import canonical_sha256, source_tree_manifest

    (tmp_path / "a.py").write_text("x = 1\n", encoding="utf-8")
    (tmp_path / "b.json").write_text("{}\n", encoding="utf-8")
    manifest = source_tree_manifest(tmp_path, ("a.py", "b.json"))
    assert manifest["schema"] == "exact_source_tree_v1"
    assert manifest["tree_sha256"] == canonical_sha256(manifest["files"])
    with pytest.raises(ValueError, match="duplicate"):
        source_tree_manifest(tmp_path, ("a.py", "a.py"))


def test_environment_fingerprint_contains_reproducibility_keys():
    from artifact_v09 import environment_fingerprint_v09

    report = environment_fingerprint_v09(IDEA_ROOT.parents[1])
    assert report["git_head"]
    assert report["python"]
    assert report["numpy"]
    assert report["pandas"]
    assert report["installed_distributions"]
    assert len(report["installed_distributions_sha256"]) == 64
