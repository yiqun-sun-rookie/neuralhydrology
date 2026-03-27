"""Tests for knowledge separation config matrix."""
import sys
from pathlib import Path

import pytest
import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

CONFIGS_DIR = Path(__file__).resolve().parents[1] / "src" / "pretrained_lstm_knowledge_separation" / "configs"

EXPECTED_ADAPTATION_CONFIGS = {
    "adapt_low_shift_head.yml": {"finetune_modules": ["head"], "shift": "low"},
    "adapt_low_shift_embedding.yml": {"finetune_modules": ["embedding_net"], "shift": "low"},
    "adapt_low_shift_lstm.yml": {"finetune_modules": ["lstm"], "shift": "low"},
    "adapt_low_shift_full.yml": {"finetune_modules": ["embedding_net", "lstm", "head"], "shift": "low"},
    "adapt_high_shift_head.yml": {"finetune_modules": ["head"], "shift": "high"},
    "adapt_high_shift_embedding.yml": {"finetune_modules": ["embedding_net"], "shift": "high"},
    "adapt_high_shift_lstm.yml": {"finetune_modules": ["lstm"], "shift": "high"},
    "adapt_high_shift_full.yml": {"finetune_modules": ["embedding_net", "lstm", "head"], "shift": "high"},
}


def _load_yaml(path: Path) -> dict:
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def test_source_config_exists():
    assert (CONFIGS_DIR / "source_pretrain.yml").is_file()


def test_source_config_uses_cudalstm():
    cfg = _load_yaml(CONFIGS_DIR / "source_pretrain.yml")
    assert cfg["model"] == "cudalstm"
    assert cfg["dataset"] == "camels_us"


@pytest.mark.parametrize("config_name,expected", list(EXPECTED_ADAPTATION_CONFIGS.items()))
def test_adaptation_config_finetune_modules(config_name, expected):
    path = CONFIGS_DIR / config_name
    assert path.is_file(), f"{config_name} not found"
    cfg = _load_yaml(path)
    assert cfg["finetune_modules"] == expected["finetune_modules"]


@pytest.mark.parametrize("config_name,expected", list(EXPECTED_ADAPTATION_CONFIGS.items()))
def test_adaptation_config_basin_file_points_to_shift_split(config_name, expected):
    cfg = _load_yaml(CONFIGS_DIR / config_name)
    shift = expected["shift"]
    expected_suffix = f"{shift}_shift_basins.txt"
    assert cfg["train_basin_file"].endswith(expected_suffix)
    assert cfg["validation_basin_file"].endswith(expected_suffix)
    assert cfg["test_basin_file"].endswith(expected_suffix)


def test_all_eight_adaptation_configs_exist():
    for name in EXPECTED_ADAPTATION_CONFIGS:
        assert (CONFIGS_DIR / name).is_file(), f"Missing: {name}"
