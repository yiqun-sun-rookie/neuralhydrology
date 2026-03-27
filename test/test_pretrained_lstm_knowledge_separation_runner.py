from pathlib import Path

import json

from src.pretrained_lstm_knowledge_separation.scripts.run_matrix import build_run_matrix, materialize_run_matrix


def _write_source_run(tmp_path: Path) -> Path:
    source_run_dir = tmp_path / "source_pretrain_run"
    source_run_dir.mkdir()
    (source_run_dir / "config.yml").write_text("experiment_name: source\n", encoding="utf-8")
    (source_run_dir / "model_epoch1.pt").write_text("weights", encoding="utf-8")
    return source_run_dir


def test_build_run_matrix_enumerates_expected_configs():
    matrix = build_run_matrix()

    assert [entry.config_name for entry in matrix] == [
        "adapt_low_shift_embedding.yml",
        "adapt_low_shift_full.yml",
        "adapt_low_shift_head.yml",
        "adapt_low_shift_lstm.yml",
        "adapt_high_shift_embedding.yml",
        "adapt_high_shift_full.yml",
        "adapt_high_shift_head.yml",
        "adapt_high_shift_lstm.yml",
    ]
    assert [entry.split_label for entry in matrix] == [
        "low_shift",
        "low_shift",
        "low_shift",
        "low_shift",
        "high_shift",
        "high_shift",
        "high_shift",
        "high_shift",
    ]
    assert [entry.adaptation_group for entry in matrix] == [
        "embedding",
        "full",
        "head",
        "lstm",
        "embedding",
        "full",
        "head",
        "lstm",
    ]


def test_materialize_run_matrix_patches_source_run_and_is_deterministic(tmp_path: Path):
    source_run_dir = _write_source_run(tmp_path)
    output_dir = tmp_path / "out"

    result = materialize_run_matrix(source_run_dir=source_run_dir, output_dir=output_dir)

    manifest = json.loads((output_dir / "manifest.json").read_text(encoding="utf-8"))
    assert len(manifest) == 8
    assert [row["config_name"] for row in manifest] == [
        "adapt_low_shift_embedding.yml",
        "adapt_low_shift_full.yml",
        "adapt_low_shift_head.yml",
        "adapt_low_shift_lstm.yml",
        "adapt_high_shift_embedding.yml",
        "adapt_high_shift_full.yml",
        "adapt_high_shift_head.yml",
        "adapt_high_shift_lstm.yml",
    ]
    assert all(row["base_run_dir"] == str(source_run_dir) for row in manifest)
    assert all(Path(row["materialized_config_path"]).is_file() for row in manifest)
    assert all("python -m neuralhydrology.nh_run finetune" in row["command"] for row in manifest)
    assert result.manifest_path == output_dir / "manifest.json"

    repeat = materialize_run_matrix(source_run_dir=source_run_dir, output_dir=tmp_path / "out_again")
    # Manifests should be structurally identical (same entries, same order) regardless of output_dir.
    manifest_repeat = json.loads(repeat.manifest_path.read_text(encoding="utf-8"))
    for a, b in zip(manifest, manifest_repeat):
        assert a["config_name"] == b["config_name"]
        assert a["split_label"] == b["split_label"]
        assert a["adaptation_group"] == b["adaptation_group"]
        assert a["base_run_dir"] == b["base_run_dir"]
