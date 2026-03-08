from pathlib import Path

from src.hbv_camels_us_531.batch import load_basin_ids, run_basin_file, summarize_results
from src.hbv_camels_us_531.runner import BasinRunResult


def test_summarize_results_computes_basic_statistics():
    results = [
        BasinRunResult("a", train_nse=0.7, validation_nse=0.6, test_nse=0.5),
        BasinRunResult("b", train_nse=0.8, validation_nse=0.7, test_nse=0.7),
        BasinRunResult("c", status="failed", error="boom"),
    ]

    summary = summarize_results(results)

    assert summary["n_basins"] == 3
    assert summary["n_success"] == 2
    assert summary["n_failed"] == 1
    assert summary["mean_test_nse"] == 0.6
    assert summary["median_test_nse"] == 0.6
    assert summary["n_test_ge_05"] == 2
    assert summary["n_test_ge_06"] == 1


def test_load_basin_ids_reads_nonempty_lines(tmp_path: Path):
    basin_file = tmp_path / "basins.txt"
    basin_file.write_text("01022500\n\n01547700\n", encoding="utf-8")

    assert load_basin_ids(basin_file) == ["01022500", "01547700"]


def test_run_basin_file_calls_runner_for_each_basin(tmp_path: Path, monkeypatch):
    basin_file = tmp_path / "basins.txt"
    basin_file.write_text("01022500\n01547700\n", encoding="utf-8")

    def fake_run_single_basin(basin_id, data_root=None):
        return BasinRunResult(basin_id=basin_id, test_nse=0.5)

    monkeypatch.setattr("src.hbv_camels_us_531.batch.run_single_basin", fake_run_single_basin)

    results = run_basin_file(basin_file)

    assert [result.basin_id for result in results] == ["01022500", "01547700"]
