import json
from pathlib import Path

import pandas as pd

from src.xaj_global_pilot.hpc.build_conceptual_benchmark_chunks import main as build_chunks_main
from src.xaj_global_pilot.hpc.preflight_conceptual_benchmark_run import main as preflight_main
from src.xaj_global_pilot.hpc.run_conceptual_benchmark_chunk import main as run_chunk_main
from src.xaj_global_pilot.hpc.summarize_conceptual_benchmark_run import main as summarize_run_main


def test_build_conceptual_benchmark_chunks_is_deterministic(tmp_path: Path):
    manifest_path = tmp_path / "camels_us_531.txt"
    manifest_path.write_text("01020304\n00000011\n00000002\n10000000\n00000003\n", encoding="utf-8")

    output_dir = tmp_path / "camels_us_531_v02"
    args = [
        "--manifest",
        str(manifest_path),
        "--output-dir",
        str(output_dir),
        "--chunk-size",
        "2",
        "--allow-scale-up",
    ]

    assert build_chunks_main(args) == 0

    chunks_dir = output_dir / "chunks"
    first_pass = {path.name: path.read_text(encoding="utf-8") for path in sorted(chunks_dir.glob("chunk_*.txt"))}
    assert list(first_pass) == ["chunk_001.txt", "chunk_002.txt", "chunk_003.txt"]
    assert first_pass["chunk_001.txt"] == "00000002\n00000003\n"
    assert first_pass["chunk_002.txt"] == "00000011\n01020304\n"
    assert first_pass["chunk_003.txt"] == "10000000\n"

    index = pd.read_csv(output_dir / "chunk_index.csv")
    assert index["chunk_file"].tolist() == ["chunk_001.txt", "chunk_002.txt", "chunk_003.txt"]
    assert index["n_basins"].tolist() == [2, 2, 1]

    assert build_chunks_main(args) == 0
    second_pass = {path.name: path.read_text(encoding="utf-8") for path in sorted(chunks_dir.glob("chunk_*.txt"))}
    assert second_pass == first_pass


def test_run_conceptual_benchmark_chunk_receives_model_chunk_trials_and_restarts(tmp_path: Path, monkeypatch):
    chunk_file = tmp_path / "chunk_002.txt"
    chunk_file.write_text("01020304\n00000011\n", encoding="utf-8")

    calls = []

    def fake_run_single_model_basin(basin_id, model, data_root=None, calibration_trials=2000):
        calls.append(
            {
                "basin_id": basin_id,
                "model": model,
                "data_root": data_root,
                "calibration_trials": calibration_trials,
            }
        )
        return {
            "basin_id": basin_id,
            "model": model,
            "period": "test",
            "nse": 0.5,
            "kge": 0.4,
            "bias": 0.0,
            "peak_bias": 0.0,
            "lowflow_bias": 0.0,
            "parameter_count": 12,
            "solver_name": "implicit_euler",
            "family": "hbv",
            "run_status": "success",
            "error_message": "",
        }

    monkeypatch.setattr(
        "src.xaj_global_pilot.hpc.run_conceptual_benchmark_chunk.run_single_model_basin",
        fake_run_single_model_basin,
    )

    output_dir = tmp_path / "camels_us_531_v02"
    assert run_chunk_main(
        [
            "--model",
            "hbv",
            "--chunk-file",
            str(chunk_file),
            "--output-dir",
            str(output_dir),
            "--data-root",
            "data/camels_us",
            "--trials",
            "7",
            "--restarts",
            "3",
        ]
    ) == 0

    assert calls == [
        {
            "basin_id": "01020304",
            "model": "hbv",
            "data_root": "data/camels_us",
            "calibration_trials": 7,
        },
        {
            "basin_id": "00000011",
            "model": "hbv",
            "data_root": "data/camels_us",
            "calibration_trials": 7,
        },
    ]

    summary_csv = output_dir / "summary" / "hbv_chunk_002.csv"
    metadata_json = output_dir / "summary" / "hbv_chunk_002.metadata.json"
    assert summary_csv.exists()
    assert metadata_json.exists()

    summary = pd.read_csv(summary_csv, dtype={"basin_id": str})
    assert summary["basin_id"].tolist() == ["00000011", "01020304"]
    assert summary["model"].tolist() == ["hbv", "hbv"]

    metadata = json.loads(metadata_json.read_text(encoding="utf-8"))
    assert metadata["model"] == "hbv"
    assert metadata["chunk_file"] == str(chunk_file)
    assert metadata["trials"] == 7
    assert metadata["restarts"] == 3


def test_run_conceptual_benchmark_chunk_skips_existing_basin_rows_when_requested(tmp_path: Path, monkeypatch):
    chunk_file = tmp_path / "chunk_003.txt"
    chunk_file.write_text("01020304\n00000011\n", encoding="utf-8")

    calls = []

    def fake_run_single_model_basin(basin_id, model, data_root=None, calibration_trials=2000):
        calls.append(basin_id)
        return {
            "basin_id": basin_id,
            "model": model,
            "period": "test",
            "nse": 0.5,
            "kge": 0.4,
            "bias": 0.0,
            "peak_bias": 0.0,
            "lowflow_bias": 0.0,
            "parameter_count": 20,
            "solver_name": "explicit_euler",
            "family": "xaj",
            "run_status": "success",
            "error_message": "",
        }

    monkeypatch.setattr(
        "src.xaj_global_pilot.hpc.run_conceptual_benchmark_chunk.run_single_model_basin",
        fake_run_single_model_basin,
    )

    output_dir = tmp_path / "camels_us_531_v02"
    existing_dir = output_dir / "xaj_pdd"
    existing_dir.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(
        [
            {
                "basin_id": "01020304",
                "model": "xaj_pdd",
                "period": "test",
                "nse": 0.9,
                "kge": 0.8,
                "bias": 0.0,
                "peak_bias": 0.0,
                "lowflow_bias": 0.0,
                "parameter_count": 20,
                "solver_name": "explicit_euler",
                "family": "xaj",
                "run_status": "success",
                "error_message": "",
            },
        ]
    ).to_csv(existing_dir / "01020304.csv", index=False)

    assert run_chunk_main(
        [
            "--model",
            "xaj_pdd",
            "--chunk-file",
            str(chunk_file),
            "--output-dir",
            str(output_dir),
            "--data-root",
            "data/camels_us",
            "--trials",
            "9",
            "--restarts",
            "1",
            "--skip-existing",
        ]
    ) == 0

    assert calls == ["00000011"]

    summary = pd.read_csv(output_dir / "summary" / "xaj_pdd_chunk_003.csv", dtype={"basin_id": str})
    assert summary["basin_id"].tolist() == ["00000011", "01020304"]
    assert summary.loc[summary["basin_id"] == "01020304", "nse"].iloc[0] == 0.9

    metadata = json.loads((output_dir / "summary" / "xaj_pdd_chunk_003.metadata.json").read_text(encoding="utf-8"))
    assert metadata["n_skipped_existing"] == 1
    assert metadata["n_executed"] == 1


def test_summarize_conceptual_benchmark_run_aggregates_primary_model_outputs(tmp_path: Path):
    manifest = tmp_path / "conceptual_benchmark_2_basins.csv"
    pd.DataFrame(
        [
            {"basin_id": "00000011", "regime": "humid"},
            {"basin_id": "01020304", "regime": "snow-dominated"},
        ]
    ).to_csv(manifest, index=False)

    output_dir = tmp_path / "camels_us_531_v02"
    for model, rows in {
        "xaj_pdd": [
            {"basin_id": "00000011", "nse": 0.6, "kge": 0.5, "parameter_count": 20, "solver_name": "explicit_euler",
             "family": "xaj", "run_status": "success", "error_message": ""},
            {"basin_id": "01020304", "nse": 0.7, "kge": 0.6, "parameter_count": 20, "solver_name": "explicit_euler",
             "family": "xaj", "run_status": "success", "error_message": ""},
        ],
        "hbv": [
            {"basin_id": "00000011", "nse": 0.5, "kge": 0.4, "parameter_count": 12, "solver_name": "implicit_euler",
             "family": "hbv", "run_status": "success", "error_message": ""},
            {"basin_id": "01020304", "nse": 0.8, "kge": 0.7, "parameter_count": 12, "solver_name": "implicit_euler",
             "family": "hbv", "run_status": "success", "error_message": ""},
        ],
        "gr4j_pdd": [
            {"basin_id": "00000011", "nse": 0.4, "kge": 0.3, "parameter_count": 10, "solver_name": "implicit_euler",
             "family": "gr4j", "run_status": "success", "error_message": ""},
            {"basin_id": "01020304", "nse": 0.2, "kge": 0.1, "parameter_count": 10, "solver_name": "implicit_euler",
             "family": "gr4j", "run_status": "success", "error_message": ""},
        ],
    }.items():
        model_dir = output_dir / model
        model_dir.mkdir(parents=True, exist_ok=True)
        for row in rows:
            full_row = {
                "model": model,
                "period": "test",
                "bias": 0.0,
                "peak_bias": 0.0,
                "lowflow_bias": 0.0,
                **row,
            }
            pd.DataFrame([full_row]).to_csv(model_dir / f"{row['basin_id']}.csv", index=False)

    assert summarize_run_main(
        [
            "--manifest",
            str(manifest),
            "--output-dir",
            str(output_dir),
        ]
    ) == 0

    summary_dir = output_dir / "summary"
    all_metrics = pd.read_csv(summary_dir / "all_basins_metrics.csv", dtype={"basin_id": str})
    completeness = pd.read_csv(summary_dir / "completeness_check.csv")
    wins = pd.read_csv(summary_dir / "win_counts.csv")

    assert len(all_metrics) == 6
    assert sorted(all_metrics["model"].unique().tolist()) == ["gr4j_pdd", "hbv", "xaj_pdd"]
    assert completeness["n_missing"].sum() == 0
    assert wins.loc[wins["model"] == "xaj_pdd", "n_best_basins"].iloc[0] == 1
    assert wins.loc[wins["model"] == "hbv", "n_best_basins"].iloc[0] == 1


def test_preflight_conceptual_benchmark_run_validates_manifest_and_chunks(tmp_path: Path):
    manifest_path = tmp_path / "camels_us_531.txt"
    manifest_path.write_text("01020304\n00000011\n00000002\n00000003\n", encoding="utf-8")
    output_dir = tmp_path / "camels_us_531_v02"

    assert build_chunks_main(
        [
            "--manifest",
            str(manifest_path),
            "--output-dir",
            str(output_dir),
            "--chunk-size",
            "2",
            "--allow-scale-up",
        ]
    ) == 0

    assert preflight_main(
        [
            "--manifest",
            str(manifest_path),
            "--output-dir",
            str(output_dir),
        ]
    ) == 0

    report = json.loads((output_dir / "preflight_report.json").read_text(encoding="utf-8"))
    assert report["n_manifest_basins"] == 4
    assert report["n_chunk_files"] == 2
    assert report["n_missing_basins"] == 0
    assert report["n_duplicate_basins"] == 0
    assert report["primary_models"] == ["xaj_pdd", "hbv", "gr4j_pdd"]


def test_preflight_ignores_non_indexed_ad_hoc_chunk_files(tmp_path: Path):
    manifest_path = tmp_path / "camels_us_531.txt"
    manifest_path.write_text("01020304\n00000011\n00000002\n00000003\n", encoding="utf-8")
    output_dir = tmp_path / "camels_us_531_v02"

    assert build_chunks_main(
        [
            "--manifest",
            str(manifest_path),
            "--output-dir",
            str(output_dir),
            "--chunk-size",
            "2",
            "--allow-scale-up",
        ]
    ) == 0

    (output_dir / "chunks" / "chunk_smoke_001.txt").write_text("01020304\n00000011\n", encoding="utf-8")

    assert preflight_main(
        [
            "--manifest",
            str(manifest_path),
            "--output-dir",
            str(output_dir),
        ]
    ) == 0
