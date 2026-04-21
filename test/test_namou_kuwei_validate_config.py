from __future__ import annotations

from pathlib import Path
import sys

import yaml


SCRIPTS_DIR = Path(__file__).resolve().parents[1] / "src" / "namou_kuwei" / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import validate_config  # noqa: E402


def _write_cfg(tmp_path: Path, cfg: dict, name: str = "cfg.yml") -> Path:
    path = tmp_path / name
    path.write_text(yaml.safe_dump(cfg, sort_keys=False), encoding="utf-8")
    return path


def _base_cfg() -> dict:
    return {
        "train_start_date": "01/01/2020",
        "train_end_date": "30/06/2021",
        "validation_start_date": "01/07/2021",
        "validation_end_date": "31/12/2021",
        "test_start_date": "01/01/2022",
        "test_end_date": "31/12/2022",
        "dynamic_inputs": ["p_aka"],
        "target_variables": ["qobs"],
        "predict_last_n": 1,
    }


def test_validate_config_rejects_earlstm_for_ar(tmp_path: Path):
    cfg = _base_cfg()
    cfg.update({
        "model": "earlstm",
        "lagged_features": {"qobs": [1]},
        "autoregressive_inputs": ["qobs_shift1"],
    })

    cfg_path = _write_cfg(tmp_path, cfg)
    is_valid, errors, warnings = validate_config.validate_config(cfg_path)

    assert is_valid is False
    assert any("does not support autoregressive_inputs" in e for e in errors)
    assert warnings == []


def test_validate_config_allows_lagged_qobs_shift_in_dynamic_inputs(tmp_path: Path):
    cfg = _base_cfg()
    cfg.update({
        "model": "gru",
        "dynamic_inputs": ["p_aka", "qobs_shift1"],
        "lagged_features": {"qobs": [1]},
    })

    cfg_path = _write_cfg(tmp_path, cfg)
    is_valid, errors, warnings = validate_config.validate_config(cfg_path)

    assert is_valid is True
    assert errors == []
    assert warnings == []


def test_model_fair_configs_are_no_leak():
    cfg_dir = Path("src/namou_kuwei/configs/no_leak/07_model_fair")
    cfg_paths = sorted(p for p in cfg_dir.glob("*.yml"))
    assert cfg_paths, "Expected fair-model configs to exist"

    for cfg_path in cfg_paths:
        cfg = yaml.safe_load(cfg_path.read_text(encoding="utf-8"))
        assert "qobs" not in cfg.get("dynamic_inputs", [])

        is_valid, errors, warnings = validate_config.validate_config(cfg_path)
        assert is_valid, f"{cfg_path.name} errors: {errors}"
        assert warnings == [], f"{cfg_path.name} warnings: {warnings}"


def test_paper_aligned_mtslstm_configs_define_expected_compressed_daily_history():
    cfg_dir = Path("src/namou_kuwei/configs/no_leak/11_mtslstm_paper_aligned")
    cfg_paths = sorted(p for p in cfg_dir.glob("*.yml"))
    assert [p.name for p in cfg_paths] == [
        "mtslstm_prev1d_pshift24_static_LT24h_y24_seq336_d365.yml",
        "mtslstm_prev1d_pshift24_static_LT24h_y24_seq336_d44.yml",
        "mtslstm_prev1d_pshift24_static_LT24h_y24_seq336_d74.yml",
    ]

    expected_extra_days = {
        "mtslstm_prev1d_pshift24_static_LT24h_y24_seq336_d44.yml": 30,
        "mtslstm_prev1d_pshift24_static_LT24h_y24_seq336_d74.yml": 60,
        "mtslstm_prev1d_pshift24_static_LT24h_y24_seq336_d365.yml": 351,
    }

    for cfg_path in cfg_paths:
        cfg = yaml.safe_load(cfg_path.read_text(encoding="utf-8"))
        assert cfg["use_frequencies"] == ["1D", "1h"]
        assert cfg["predict_last_n"] == {"1D": 1, "1h": 24}
        assert cfg["seq_length"]["1h"] == 336

        compressed_daily_history = cfg["seq_length"]["1D"] - int(cfg["seq_length"]["1h"] / 24)
        assert compressed_daily_history == expected_extra_days[cfg_path.name]

        is_valid, errors, warnings = validate_config.validate_config(cfg_path)
        assert is_valid, f"{cfg_path.name} errors: {errors}"
        assert warnings == [], f"{cfg_path.name} warnings: {warnings}"
