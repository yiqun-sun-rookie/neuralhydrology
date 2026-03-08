import pandas as pd

from src.hbv_camels_us_531.runner import BasinRunResult, run_single_basin, split_periods


def test_split_periods_returns_three_named_windows():
    periods = split_periods()

    assert periods["train"] == ("1990-10-01", "1995-09-30")
    assert periods["validation"] == ("1995-10-01", "2000-09-30")
    assert periods["test"] == ("2000-10-01", "2005-09-30")


def test_basin_run_result_defaults():
    result = BasinRunResult(basin_id="01022500")

    assert result.basin_id == "01022500"
    assert result.train_nse is None
    assert result.validation_nse is None
    assert result.test_nse is None
    assert result.status == "ok"
    assert result.error == ""
    assert result.best_params == {}


def test_run_single_basin_returns_result_with_metrics(monkeypatch):
    def fake_loader(basin_id, data_root=None, start_date=None, end_date=None):
        idx = pd.date_range(start_date, periods=3, freq="D")
        forcing = pd.DataFrame({"prcp": [1.0, 1.0, 1.0], "ep": [0.2, 0.2, 0.2], "tmean": [5.0, 5.0, 5.0]}, index=idx)
        obs = pd.Series([1.0, 2.0, 3.0], index=idx)
        return forcing, obs, 100.0

    class FakeEnv:
        def parse_structure(self, structure_json):
            self.structure_json = structure_json

        def auto_calibrate(self, forcing_data, obs_data):
            return {"nse": 0.7, "optimized_params": {"soil_Smax": 100.0}, "qsim": obs_data.copy()}

        def run_simulation(self, forcing_data, params=None):
            return pd.Series([1.0, 2.0, 3.0], index=forcing_data.index)

    monkeypatch.setattr("src.hbv_camels_us_531.runner.load_camels_basin", fake_loader)
    monkeypatch.setattr("src.hbv_camels_us_531.runner.SuperflexEnv", FakeEnv)

    result = run_single_basin("01022500")

    assert result.status == "ok"
    assert result.train_nse == 0.7
    assert result.validation_nse == 1.0
    assert result.test_nse == 1.0
    assert result.best_params == {"soil_Smax": 100.0}
