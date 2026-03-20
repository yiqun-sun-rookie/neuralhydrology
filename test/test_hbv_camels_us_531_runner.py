import pandas as pd
import numpy as np

from src.hydroagent import environment as hydro_environment
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
    assert result.bounds_profile == "primary"


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
    assert result.bounds_profile == "primary"


def test_run_single_basin_retries_with_fallback_bounds_profile(monkeypatch):
    calls = []

    def fake_loader(basin_id, data_root=None, start_date=None, end_date=None):
        idx = pd.date_range(start_date, periods=3, freq="D")
        forcing = pd.DataFrame({"prcp": [1.0, 1.0, 1.0], "ep": [0.2, 0.2, 0.2], "tmean": [5.0, 5.0, 5.0]}, index=idx)
        obs = pd.Series([1.0, 2.0, 3.0], index=idx)
        return forcing, obs, 100.0

    class FakeEnv:
        def parse_structure(self, structure_json):
            self.structure_json = structure_json

        def auto_calibrate(self, forcing_data, obs_data):
            calls.append((
                hydro_environment._REGISTRY["UnsaturatedReservoir"]["bounds"]["beta"],
                hydro_environment._REGISTRY["PowerReservoir"]["bounds"]["alpha"],
                hydro_environment._REGISTRY["SnowReservoir"]["bounds"]["k"],
            ))
            if hydro_environment._REGISTRY["PowerReservoir"]["bounds"]["alpha"] == (1.0, 3.0):
                raise RuntimeError("primary profile failed")
            return {"nse": 0.7, "optimized_params": {"soil_Smax": 100.0}, "qsim": obs_data.copy()}

        def run_simulation(self, forcing_data, params=None):
            return pd.Series([1.0, 2.0, 3.0], index=forcing_data.index)

    monkeypatch.setattr("src.hbv_camels_us_531.runner.load_camels_basin", fake_loader)
    monkeypatch.setattr("src.hbv_camels_us_531.runner.SuperflexEnv", FakeEnv)

    result = run_single_basin("01022500")

    assert result.status == "ok"
    assert result.bounds_profile == "fallback"
    assert calls == [
        ((1.0, 5.0), (1.0, 3.0), (0.5, 5.0)),
        ((1.0, 5.0), (1.0, 2.5), (0.5, 5.0)),
    ]


def test_run_single_basin_returns_failed_result_on_calibration_error(monkeypatch):
    def fake_loader(basin_id, data_root=None, start_date=None, end_date=None):
        idx = pd.date_range(start_date, periods=3, freq="D")
        forcing = pd.DataFrame({"prcp": [1.0, 1.0, 1.0], "ep": [0.2, 0.2, 0.2], "tmean": [5.0, 5.0, 5.0]}, index=idx)
        obs = pd.Series([1.0, 2.0, 3.0], index=idx)
        return forcing, obs, 100.0

    class FakeEnv:
        def parse_structure(self, structure_json):
            self.structure_json = structure_json

        def auto_calibrate(self, forcing_data, obs_data):
            raise RuntimeError("calibration failed")

    monkeypatch.setattr("src.hbv_camels_us_531.runner.load_camels_basin", fake_loader)
    monkeypatch.setattr("src.hbv_camels_us_531.runner.SuperflexEnv", FakeEnv)

    result = run_single_basin("01022500")

    assert result.status == "failed"
    assert "calibration failed" in result.error


def test_run_single_basin_returns_failed_result_on_empty_observations(monkeypatch):
    def fake_loader(basin_id, data_root=None, start_date=None, end_date=None):
        idx = pd.date_range(start_date, periods=0, freq="D")
        forcing = pd.DataFrame({"prcp": [], "ep": [], "tmean": []}, index=idx)
        obs = pd.Series([], dtype=float, index=idx)
        return forcing, obs, 100.0

    class FakeEnv:
        def parse_structure(self, structure_json):
            self.structure_json = structure_json

        def auto_calibrate(self, forcing_data, obs_data):
            raise AssertionError("should not calibrate empty data")

    monkeypatch.setattr("src.hbv_camels_us_531.runner.load_camels_basin", fake_loader)
    monkeypatch.setattr("src.hbv_camels_us_531.runner.SuperflexEnv", FakeEnv)

    result = run_single_basin("01022500")

    assert result.status == "failed"
    assert "empty" in result.error.lower()


def test_run_single_basin_returns_failed_result_on_non_finite_simulation(monkeypatch):
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
            return pd.Series([1.0, np.inf, 3.0], index=forcing_data.index)

    monkeypatch.setattr("src.hbv_camels_us_531.runner.load_camels_basin", fake_loader)
    monkeypatch.setattr("src.hbv_camels_us_531.runner.SuperflexEnv", FakeEnv)

    result = run_single_basin("01022500")

    assert result.status == "failed"
    assert "non-finite" in result.error.lower()


def test_run_single_basin_temporarily_hardens_soil_beta_lower_bound(monkeypatch):
    seen_bounds = []
    original_bounds = hydro_environment._REGISTRY["UnsaturatedReservoir"]["bounds"]["beta"]
    original_fast_alpha_bounds = hydro_environment._REGISTRY["PowerReservoir"]["bounds"]["alpha"]
    original_snow_k_bounds = hydro_environment._REGISTRY["SnowReservoir"]["bounds"]["k"]

    def fake_loader(basin_id, data_root=None, start_date=None, end_date=None):
        idx = pd.date_range(start_date, periods=3, freq="D")
        forcing = pd.DataFrame({"prcp": [1.0, 1.0, 1.0], "ep": [0.2, 0.2, 0.2], "tmean": [5.0, 5.0, 5.0]}, index=idx)
        obs = pd.Series([1.0, 2.0, 3.0], index=idx)
        return forcing, obs, 100.0

    class FakeEnv:
        def parse_structure(self, structure_json):
            self.structure_json = structure_json

        def auto_calibrate(self, forcing_data, obs_data):
            seen_bounds.append(hydro_environment._REGISTRY["UnsaturatedReservoir"]["bounds"]["beta"])
            seen_bounds.append(hydro_environment._REGISTRY["PowerReservoir"]["bounds"]["alpha"])
            seen_bounds.append(hydro_environment._REGISTRY["SnowReservoir"]["bounds"]["k"])
            return {"nse": 0.7, "optimized_params": {"soil_Smax": 100.0}, "qsim": obs_data.copy()}

        def run_simulation(self, forcing_data, params=None):
            return pd.Series([1.0, 2.0, 3.0], index=forcing_data.index)

    monkeypatch.setattr("src.hbv_camels_us_531.runner.load_camels_basin", fake_loader)
    monkeypatch.setattr("src.hbv_camels_us_531.runner.SuperflexEnv", FakeEnv)

    result = run_single_basin("01022500")

    assert result.status == "ok"
    assert seen_bounds == [(1.0, 5.0), (1.0, 3.0), (0.5, 5.0)]
    assert hydro_environment._REGISTRY["UnsaturatedReservoir"]["bounds"]["beta"] == original_bounds
    assert hydro_environment._REGISTRY["PowerReservoir"]["bounds"]["alpha"] == original_fast_alpha_bounds
    assert hydro_environment._REGISTRY["SnowReservoir"]["bounds"]["k"] == original_snow_k_bounds
