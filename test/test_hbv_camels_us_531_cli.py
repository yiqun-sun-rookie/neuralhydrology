from src.hbv_camels_us_531.scripts.run_hbv_camels_us_531 import build_parser, run_from_args


def test_cli_accepts_single_and_batch_modes():
    parser = build_parser()

    args = parser.parse_args(["--basin-id", "01022500"])
    assert args.basin_id == "01022500"

    args = parser.parse_args(["--basin-file", "src/full_531_basins/data/531_basin_list.txt"])
    assert args.basin_file.endswith("531_basin_list.txt")


def test_run_from_args_dispatches_single_and_batch(monkeypatch):
    calls = []

    def fake_run_single_basin(basin_id, data_root=None):
        calls.append(("single", basin_id, data_root))
        return {"mode": "single"}

    def fake_run_basin_file(basin_file, data_root=None):
        calls.append(("batch", basin_file, data_root))
        return [{"mode": "batch"}]

    monkeypatch.setattr("src.hbv_camels_us_531.scripts.run_hbv_camels_us_531.run_single_basin", fake_run_single_basin)
    monkeypatch.setattr("src.hbv_camels_us_531.scripts.run_hbv_camels_us_531.run_basin_file", fake_run_basin_file)

    parser = build_parser()
    single_args = parser.parse_args(["--basin-id", "01022500"])
    batch_args = parser.parse_args(["--basin-file", "basins.txt"])

    assert run_from_args(single_args) == {"mode": "single"}
    assert run_from_args(batch_args) == [{"mode": "batch"}]
    assert calls == [
        ("single", "01022500", None),
        ("batch", "basins.txt", None),
    ]
