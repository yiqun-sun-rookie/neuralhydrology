import numpy as np
import pandas as pd

from src.xaj_global_pilot.runner import run_single_model_basin


def test_run_single_model_basin_returns_metrics_row_xaj(monkeypatch):
    """XAJ 模型走 NumPy 路径，mock calibrate_xaj 和 simulate_xaj。"""
    def fake_load(basin_id, data_root=None, start_date=None, end_date=None):
        idx = pd.date_range(start_date, periods=3, freq="D")
        forcing = pd.DataFrame({"prcp": [1.0, 1.0, 1.0], "ep": [0.2, 0.2, 0.2], "tmean": [3.0, 3.0, 3.0]}, index=idx)
        obs = pd.Series([0.5, 1.0, 1.5], index=idx)
        return forcing, obs, 100.0

    call_log = []

    def fake_calibrate(rain, pet, obs, n_trials=2000):
        call_log.append(("calibrate", n_trials))
        return {
            "nse": 0.62,
            "optimized_params": {"kc": 1.0, "b": 0.4, "wum": 30.0, "wlm": 60.0, "wdm": 20.0,
                                 "sm": 20.0, "imp": 0.1, "c": 0.12, "ex": 1.5,
                                 "ki": 0.35, "kg": 0.35, "cs": 0.6, "ci": 0.7, "cg": 0.8},
            "final_state": np.zeros((1, 8)),
        }

    def fake_simulate(rain, pet, params, initial_state=None):
        # 返回与 test obs 完全匹配的 Q
        q = np.array([0.5, 1.0, 1.5])[:len(rain)]
        return q, np.zeros((1, 8))

    monkeypatch.setattr("src.xaj_global_pilot.runner.load_camels_basin", fake_load)
    monkeypatch.setattr("src.xaj_global_pilot.runner.calibrate_xaj", fake_calibrate)
    monkeypatch.setattr("src.xaj_global_pilot.runner.simulate_xaj", fake_simulate)

    result = run_single_model_basin("01022500", "xaj", "data/camels_us")

    assert result["basin_id"] == "01022500"
    assert result["model"] == "xaj"
    assert result["period"] == "test"
    assert result["nse"] == 1.0
    assert result["kge"] == 1.0
    assert result["parameter_count"] == 14
    assert result["solver_name"] == "explicit_euler"
    assert result["family"] == "xaj"
    assert result["run_status"] == "success"


def test_run_single_model_basin_supports_caravan_inputs(monkeypatch):
    """HBV (SuperflexPy) 通过 Caravan 数据加载。"""
    def fake_load_caravan(*, data_dir, basin):
        idx = pd.date_range("1981-01-01", "2011-01-03", freq="D")
        return pd.DataFrame(
            {
                "total_precipitation_sum": [1.0] * len(idx),
                "potential_evaporation_sum_ERA5_LAND": [0.2] * len(idx),
                "temperature_2m_mean": [2.0] * len(idx),
                "streamflow": [0.2] * len(idx),
            },
            index=idx,
        )

    class FakeEnv:
        def parse_structure(self, structure_json):
            self.structure_json = structure_json

        def auto_calibrate(self, forcing_data, obs_data):
            return {"nse": 0.5, "optimized_params": {"snow_k": 1.0}, "qsim": obs_data.copy()}

        def run_simulation(self, forcing_data, params=None):
            return pd.Series([0.2] * len(forcing_data), index=forcing_data.index)

    monkeypatch.setattr("src.xaj_global_pilot.runner.load_caravan_timeseries", fake_load_caravan)
    monkeypatch.setattr("src.xaj_global_pilot.runner.SuperflexEnv", FakeEnv)

    result = run_single_model_basin("camels_01022500", "hbv", "data/Caravan")

    assert result["basin_id"] == "camels_01022500"
    assert result["model"] == "hbv"
    assert result["parameter_count"] == 12
    assert result["solver_name"] == "implicit_euler"
    assert result["family"] == "hbv"
    assert result["run_status"] == "success"


def test_run_single_model_basin_supports_gr4j_pdd(monkeypatch):
    def fake_load(basin_id, data_root=None, start_date=None, end_date=None):
        idx = pd.date_range(start_date, periods=3, freq="D")
        forcing = pd.DataFrame(
            {"prcp": [1.0, 1.0, 1.0], "ep": [0.2, 0.2, 0.2], "tmean": [3.0, 3.0, 3.0]},
            index=idx,
        )
        obs = pd.Series([0.5, 1.0, 1.5], index=idx)
        return forcing, obs, 100.0

    class FakeEnv:
        def parse_structure(self, structure_json):
            self.structure_json = structure_json

        def _calibrate_sfpy(self, forcing_data, obs_data, n_trials=200):
            return {"nse": 0.5, "optimized_params": {"routing_x3": 50.0}, "qsim": obs_data.copy()}

        def run_simulation(self, forcing_data, params=None):
            return pd.Series([0.5, 1.0, 1.5], index=forcing_data.index)

    monkeypatch.setattr("src.xaj_global_pilot.runner.load_camels_basin", fake_load)
    monkeypatch.setattr("src.xaj_global_pilot.runner.SuperflexEnv", FakeEnv)

    result = run_single_model_basin("01022500", "gr4j_pdd", "data/camels_us")

    assert result["model"] == "gr4j_pdd"
    assert result["parameter_count"] == 10
    assert result["solver_name"] == "implicit_euler"
    assert result["family"] == "gr4j"
    assert result["run_status"] == "success"


def test_run_single_model_basin_clips_negative_caravan_ep(monkeypatch):
    """Caravan 数据的负 EP 被 clip 到 0（HBV SuperflexPy 路径）。"""
    seen_ep_min = []

    def fake_load_caravan(*, data_dir, basin):
        idx = pd.DatetimeIndex(
            list(pd.date_range("1990-10-01", periods=3, freq="D"))
            + list(pd.date_range("2000-10-01", periods=3, freq="D"))
        )
        ep = [-0.2, 0.2, -0.1, 0.1, 0.2, 0.3]
        return pd.DataFrame(
            {
                "total_precipitation_sum": [1.0] * len(idx),
                "potential_evaporation_sum_ERA5_LAND": ep,
                "temperature_2m_mean": [2.0] * len(idx),
                "streamflow": [0.2] * len(idx),
            },
            index=idx,
        )

    class FakeEnv:
        def parse_structure(self, structure_json):
            self.structure_json = structure_json

        def _calibrate_sfpy(self, forcing_data, obs_data, n_trials=200):
            seen_ep_min.append(float(forcing_data["ep"].min()))
            return {"nse": 0.5, "optimized_params": {"snow_k": 1.0}, "qsim": obs_data.copy()}

        def run_simulation(self, forcing_data, params=None):
            return pd.Series([0.2] * len(forcing_data), index=forcing_data.index)

    monkeypatch.setattr("src.xaj_global_pilot.runner.load_caravan_timeseries", fake_load_caravan)
    monkeypatch.setattr("src.xaj_global_pilot.runner.SuperflexEnv", FakeEnv)

    result = run_single_model_basin("camels_01022500", "hbv", "data/Caravan")

    assert result["run_status"] == "success"
    assert seen_ep_min == [0.0]


def test_run_single_model_basin_xaj_passes_calibration_trials(monkeypatch):
    """验证 calibration_trials 能传递到 NumPy XAJ 率定。"""
    seen_trials = []

    def fake_load(basin_id, data_root=None, start_date=None, end_date=None):
        idx = pd.date_range(start_date, periods=3, freq="D")
        forcing = pd.DataFrame({"prcp": [1.0, 1.0, 1.0], "ep": [0.2, 0.2, 0.2], "tmean": [3.0, 3.0, 3.0]}, index=idx)
        obs = pd.Series([0.5, 1.0, 1.5], index=idx)
        return forcing, obs, 100.0

    def fake_calibrate(rain, pet, obs, n_trials=2000):
        seen_trials.append(n_trials)
        return {
            "nse": 0.62,
            "optimized_params": {"kc": 1.0, "b": 0.4, "wum": 30.0, "wlm": 60.0, "wdm": 20.0,
                                 "sm": 20.0, "imp": 0.1, "c": 0.12, "ex": 1.5,
                                 "ki": 0.35, "kg": 0.35, "cs": 0.6, "ci": 0.7, "cg": 0.8},
            "final_state": np.zeros((1, 8)),
        }

    def fake_simulate(rain, pet, params, initial_state=None):
        return np.array([0.5, 1.0, 1.5])[:len(rain)], np.zeros((1, 8))

    monkeypatch.setattr("src.xaj_global_pilot.runner.load_camels_basin", fake_load)
    monkeypatch.setattr("src.xaj_global_pilot.runner.calibrate_xaj", fake_calibrate)
    monkeypatch.setattr("src.xaj_global_pilot.runner.simulate_xaj", fake_simulate)

    result = run_single_model_basin("01022500", "xaj", "data/camels_us", calibration_trials=7)

    assert result["run_status"] == "success"
    assert seen_trials == [7]


def test_run_single_model_basin_superflexpy_falls_back_to_default_params(monkeypatch):
    """SuperflexPy 路径 (hbv) 率定失败时退回默认参数。"""
    attempted_params = []

    def fake_load(basin_id, data_root=None, start_date=None, end_date=None):
        idx = pd.date_range(start_date, periods=3, freq="D")
        forcing = pd.DataFrame({"prcp": [1.0, 1.0, 1.0], "ep": [0.2, 0.2, 0.2], "tmean": [3.0, 3.0, 3.0]}, index=idx)
        obs = pd.Series([0.5, 1.0, 1.5], index=idx)
        return forcing, obs, 100.0

    class FakeEnv:
        def parse_structure(self, structure_json):
            self.structure_json = structure_json

        def _calibrate_sfpy(self, forcing_data, obs_data, n_trials=200):
            return {"nse": -999.0, "optimized_params": {"soil_Smax": 500.0}, "qsim": obs_data.copy()}

        def run_simulation(self, forcing_data, params=None):
            attempted_params.append(params)
            if params:
                raise ValueError("superflexpy solver error")
            return pd.Series([0.5, 1.0, 1.5], index=forcing_data.index)

    monkeypatch.setattr("src.xaj_global_pilot.runner.load_camels_basin", fake_load)
    monkeypatch.setattr("src.xaj_global_pilot.runner.SuperflexEnv", FakeEnv)

    result = run_single_model_basin("01022500", "hbv", "data/camels_us", calibration_trials=7)

    assert result["run_status"] == "success"
    assert result["nse"] == 1.0
    assert attempted_params == [None]


def test_run_single_model_basin_superflexpy_uses_fresh_env(monkeypatch):
    """SuperflexPy 路径 (hbv) 率定失败后用新实例跑测试。"""
    instance_count = 0

    def fake_load(basin_id, data_root=None, start_date=None, end_date=None):
        idx = pd.date_range(start_date, periods=3, freq="D")
        forcing = pd.DataFrame({"prcp": [1.0, 1.0, 1.0], "ep": [0.2, 0.2, 0.2], "tmean": [3.0, 3.0, 3.0]}, index=idx)
        obs = pd.Series([0.5, 1.0, 1.5], index=idx)
        return forcing, obs, 100.0

    class FakeEnv:
        def __init__(self):
            nonlocal instance_count
            instance_count += 1
            self.was_calibrated = False

        def parse_structure(self, structure_json):
            self.structure_json = structure_json

        def _calibrate_sfpy(self, forcing_data, obs_data, n_trials=200):
            self.was_calibrated = True
            return {"nse": -999.0, "optimized_params": {"soil_Smax": 500.0}, "qsim": obs_data.copy()}

        def run_simulation(self, forcing_data, params=None):
            if self.was_calibrated:
                raise ValueError("calibration poisoned this env instance")
            return pd.Series([0.5, 1.0, 1.5], index=forcing_data.index)

    monkeypatch.setattr("src.xaj_global_pilot.runner.load_camels_basin", fake_load)
    monkeypatch.setattr("src.xaj_global_pilot.runner.SuperflexEnv", FakeEnv)

    result = run_single_model_basin("01022500", "hbv", "data/camels_us", calibration_trials=7)

    assert result["run_status"] == "success"
    assert result["nse"] == 1.0
    assert instance_count == 2


def test_run_single_model_basin_pdd_xaj_passes_calibration_trials(monkeypatch):
    """验证 PDD+XAJ 模型 calibration_trials 传递。"""
    seen_trials = []

    def fake_load(basin_id, data_root=None, start_date=None, end_date=None):
        idx = pd.date_range(start_date, periods=3, freq="D")
        forcing = pd.DataFrame({"prcp": [1.0]*3, "ep": [0.2]*3, "tmean": [3.0]*3}, index=idx)
        obs = pd.Series([0.5, 1.0, 1.5], index=idx)
        return forcing, obs, 100.0

    def fake_calibrate(rain, pet, temp, obs, n_trials=5000):
        seen_trials.append(n_trials)
        return {
            "nse": 0.5,
            "optimized_params": {
                "pdd_factor_snow": 3.0, "pdd_factor_ice": 8.0,
                "refreeze_snow": 0.1, "refreeze_ice": 0.1,
                "temp_snow": 0.0, "temp_rain": 2.0,
                "kc": 1.0, "b": 0.4, "wum": 30.0, "wlm": 60.0, "wdm": 20.0,
                "sm": 20.0, "imp": 0.1, "c": 0.12, "ex": 1.5,
                "ki": 0.35, "kg": 0.35, "cs": 0.6, "ci": 0.7, "cg": 0.8,
            },
            "final_state": np.zeros((1, 11)),
        }

    def fake_simulate(rain, pet, temp, params, initial_state=None):
        return np.array([0.5, 1.0, 1.5])[:len(rain)], np.zeros((1, 11))

    monkeypatch.setattr("src.xaj_global_pilot.runner.load_camels_basin", fake_load)
    monkeypatch.setattr("src.xaj_global_pilot.runner.calibrate_pdd_xaj", fake_calibrate)
    monkeypatch.setattr("src.xaj_global_pilot.runner.simulate_pdd_xaj", fake_simulate)

    result = run_single_model_basin("01022500", "xaj_pdd", "data/camels_us", calibration_trials=100)

    assert result["run_status"] == "success"
    assert seen_trials == [100]


def test_run_single_model_basin_xaj_uses_train_final_state(monkeypatch):
    """验证 XAJ 测试期使用训练期末状态作为初始条件。"""
    simulate_calls = []

    def fake_load(basin_id, data_root=None, start_date=None, end_date=None):
        idx = pd.date_range(start_date, periods=5, freq="D")
        forcing = pd.DataFrame({"prcp": [2.0]*5, "ep": [0.5]*5, "tmean": [10.0]*5}, index=idx)
        obs = pd.Series([0.5, 1.0, 1.5, 2.0, 2.5], index=idx)
        return forcing, obs, 100.0

    train_final = np.array([[50.0, 20.0, 30.0, 10.0, 8.0, 0.3, 0.2, 0.1]])

    def fake_calibrate(rain, pet, obs, n_trials=2000):
        return {
            "nse": 0.62,
            "optimized_params": {"kc": 1.0, "b": 0.4, "wum": 30.0, "wlm": 60.0, "wdm": 20.0,
                                 "sm": 20.0, "imp": 0.1, "c": 0.12, "ex": 1.5,
                                 "ki": 0.35, "kg": 0.35, "cs": 0.6, "ci": 0.7, "cg": 0.8},
            "final_state": np.zeros((1, 8)),
        }

    def fake_simulate(rain, pet, params, initial_state=None):
        simulate_calls.append({"initial_state": initial_state is not None})
        # 第 1 次 (train): 返回训练末状态
        if initial_state is None:
            return np.array([0.5, 1.0, 1.5, 2.0, 2.5])[:len(rain)], train_final.copy()
        # 第 2 次 (test): 返回与 obs 匹配的 Q
        return np.array([0.5, 1.0, 1.5, 2.0, 2.5])[:len(rain)], np.zeros((1, 8))

    monkeypatch.setattr("src.xaj_global_pilot.runner.load_camels_basin", fake_load)
    monkeypatch.setattr("src.xaj_global_pilot.runner.calibrate_xaj", fake_calibrate)
    monkeypatch.setattr("src.xaj_global_pilot.runner.simulate_xaj", fake_simulate)

    result = run_single_model_basin("01022500", "xaj", "data/camels_us")

    assert result["run_status"] == "success"
    # simulate 被调用 2 次：第 1 次跑 train 取末状态，第 2 次跑 test
    assert len(simulate_calls) == 2
    assert simulate_calls[0]["initial_state"] is False   # train: 无初始状态
    assert simulate_calls[1]["initial_state"] is True     # test: 使用训练末状态


def test_run_single_model_basin_superflexpy_falls_back_when_parametrized_simulation_is_all_nan(monkeypatch):
    """SuperflexPy 路径在带参数测试期输出全 NaN 时回退到默认参数。"""
    attempted_params = []
    instance_count = 0

    def fake_load(basin_id, data_root=None, start_date=None, end_date=None):
        idx = pd.date_range(start_date, periods=3, freq="D")
        forcing = pd.DataFrame({"prcp": [1.0, 1.0, 1.0], "ep": [0.2, 0.2, 0.2], "tmean": [3.0, 3.0, 3.0]}, index=idx)
        obs = pd.Series([0.5, 1.0, 1.5], index=idx)
        return forcing, obs, 100.0

    class FakeEnv:
        def __init__(self):
            nonlocal instance_count
            instance_count += 1
            self.current_params = None

        def parse_structure(self, structure_json):
            self.structure_json = structure_json

        def _calibrate_sfpy(self, forcing_data, obs_data, n_trials=200):
            return {"nse": 0.4, "optimized_params": {"routing_x3": 50.0}, "qsim": obs_data.copy()}

        def run_simulation(self, forcing_data, params=None):
            attempted_params.append(params)
            if params:
                self.current_params = params
            if self.current_params:
                return pd.Series([np.nan] * len(forcing_data), index=forcing_data.index)
            return pd.Series([0.5, 1.0, 1.5], index=forcing_data.index)

    monkeypatch.setattr("src.xaj_global_pilot.runner.load_camels_basin", fake_load)
    monkeypatch.setattr("src.xaj_global_pilot.runner.SuperflexEnv", FakeEnv)

    result = run_single_model_basin("01022500", "gr4j", "data/camels_us", calibration_trials=7)

    assert result["run_status"] == "success"
    assert result["nse"] == 1.0
    assert attempted_params == [{"routing_x3": 50.0}, None]
    assert instance_count == 3
