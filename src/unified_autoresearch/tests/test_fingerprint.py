import os
import subprocess
from pathlib import Path

import pytest


REQUIRED_COMPONENTS = {
    "git_commit",
    "code",
    "uncommitted_diff",
    "configuration",
    "dependencies",
    "data_manifest",
    "random_seeds",
    "artifacts",
}


def _git(repo: Path, *args: str) -> None:
    subprocess.run(["git", *args], cwd=repo, check=True, capture_output=True, text=True)


def _repo(tmp_path: Path) -> dict[str, Path]:
    repo = tmp_path / "repo"
    repo.mkdir()
    _git(repo, "init")
    _git(repo, "config", "user.email", "test@example.invalid")
    _git(repo, "config", "user.name", "Test")
    paths = {
        "repo": repo,
        "code": repo / "model.py",
        "config": repo / "config.json",
        "dependencies": repo / "requirements.txt",
        "data": repo / "data_manifest.json",
        "artifact_dir": repo / "artifacts",
        "artifact": repo / "artifacts" / "artifact.bin",
        "untracked": repo / "scratch.txt",
    }
    paths["artifact_dir"].mkdir()
    paths["code"].write_text("VALUE = 1\n", encoding="utf-8")
    paths["config"].write_text('{"epochs": 1}\n', encoding="utf-8")
    paths["dependencies"].write_text("numpy\n", encoding="utf-8")
    paths["data"].write_text('{"basins": 8}\n', encoding="utf-8")
    paths["artifact"].write_bytes(b"artifact-v1")
    _git(repo, "add", ".")
    _git(repo, "commit", "-m", "fixture")
    paths["untracked"].write_text("untracked-v1\n", encoding="utf-8")
    return paths


def _build(paths: dict[str, Path], seeds=(11, 22)):
    from unified_autoresearch.registry.fingerprint import build_fingerprint

    return build_fingerprint(
        repo_root=paths["repo"],
        code_paths=[paths["code"]],
        configuration_paths=[paths["config"]],
        dependency_paths=[paths["dependencies"]],
        data_manifest_paths=[paths["data"]],
        random_seeds=list(seeds),
        artifact_paths=[paths["artifact_dir"]],
    )


def test_fingerprint_contains_every_required_component_as_sha256(tmp_path):
    fingerprint = _build(_repo(tmp_path))
    assert set(fingerprint["components"]) == REQUIRED_COMPONENTS
    assert all(len(value) == 64 and int(value, 16) >= 0 for value in fingerprint["components"].values())
    assert len(fingerprint["root_sha256"]) == 64
    assert fingerprint["details"]["random_seeds"] == [11, 22]


def test_seed_change_changes_only_seed_component_and_root(tmp_path):
    paths = _repo(tmp_path)
    before = _build(paths, seeds=(11, 22))
    after = _build(paths, seeds=(11, 23))
    changed = {name for name in REQUIRED_COMPONENTS if before["components"][name] != after["components"][name]}
    assert changed == {"random_seeds"}
    assert before["root_sha256"] != after["root_sha256"]


def test_untracked_difference_is_covered_even_when_not_in_code_paths(tmp_path):
    paths = _repo(tmp_path)
    before = _build(paths)
    paths["untracked"].write_text("untracked-v2\n", encoding="utf-8")
    after = _build(paths)
    assert before["components"]["uncommitted_diff"] != after["components"]["uncommitted_diff"]
    assert before["components"]["code"] == after["components"]["code"]
    assert before["root_sha256"] != after["root_sha256"]


def test_configuration_dependency_data_and_artifact_changes_are_covered(tmp_path):
    paths = _repo(tmp_path)
    mutations = [
        ("config", "configuration", b'{"epochs": 2}\n'),
        ("dependencies", "dependencies", b"numpy\npandas\n"),
        ("data", "data_manifest", b'{"basins": 9}\n'),
        ("artifact", "artifacts", b"artifact-v2"),
    ]
    for path_name, component, replacement in mutations:
        before = _build(paths)
        paths[path_name].write_bytes(replacement)
        after = _build(paths)
        assert before["components"][component] != after["components"][component]
        assert before["root_sha256"] != after["root_sha256"]


def test_artifact_inputs_must_be_directory_roots_so_unlisted_outputs_cannot_be_omitted(tmp_path):
    from unified_autoresearch.registry.fingerprint import build_fingerprint

    paths = _repo(tmp_path)
    with pytest.raises(ValueError, match="artifact paths must be directory roots"):
        build_fingerprint(
            repo_root=paths["repo"],
            code_paths=[paths["code"]],
            configuration_paths=[paths["config"]],
            dependency_paths=[paths["dependencies"]],
            data_manifest_paths=[paths["data"]],
            random_seeds=[11, 22],
            artifact_paths=[paths["artifact"]],
        )

    before = _build(paths)
    (paths["artifact_dir"] / "ignored-output.bin").write_bytes(b"must-be-covered")
    after = _build(paths)
    assert before["components"]["artifacts"] != after["components"]["artifacts"]
    assert before["root_sha256"] != after["root_sha256"]


@pytest.mark.skipif(os.name != "nt", reason="Windows extended-length paths are Windows-specific")
def test_artifact_manifest_includes_files_beyond_the_windows_legacy_path_limit(tmp_path):
    paths = _repo(tmp_path)
    relative = Path("deep") / ("x" * 150) / "CHECKPOINT_VERIFIED.json"
    deep_file = paths["artifact_dir"] / relative
    os.makedirs("\\\\?\\" + str(deep_file.parent.resolve()), exist_ok=True)
    payload = b"long-path-checkpoint-evidence"
    with open("\\\\?\\" + str(deep_file.resolve()), "xb") as stream:
        stream.write(payload)
    assert len(str(deep_file)) > 260

    fingerprint = _build(paths)

    label = deep_file.relative_to(paths["repo"]).as_posix()
    recorded = {entry["path"]: entry for entry in fingerprint["details"]["artifacts"]}
    assert recorded[label]["bytes"] == len(payload)
