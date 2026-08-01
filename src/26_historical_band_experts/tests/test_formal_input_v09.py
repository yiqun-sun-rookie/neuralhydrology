from pathlib import Path
import sys

import numpy as np
import pytest


IDEA_ROOT = Path(__file__).resolve().parents[1]
TEST_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(IDEA_ROOT))
sys.path.insert(0, str(TEST_ROOT))

from synthetic_input_case_v09 import build_synthetic_case, make_synthetic_input_case


def test_synthetic_builder_creates_exact_sealed_artifacts_and_loader_hides_raw_statics(tmp_path):
    from formal_input_v09 import SEALED_ARTIFACTS_V09, load_sealed_inputs_v09

    case, root = build_synthetic_case(tmp_path)
    assert sorted(path.name for path in root.iterdir()) == sorted(SEALED_ARTIFACTS_V09)
    loaded = load_sealed_inputs_v09(
        root,
        contract=case["contract"],
        data_root=case["data_root"],
        static_path=case["static_path"],
        target_path=case["target_path"],
    )
    assert set(loaded) == {"basins", "dates", "target_dates", "forcing", "statics", "targets", "scaler"}
    assert loaded["forcing"].shape == (3, 5, 5)
    assert loaded["targets"].shape == (3, 3)
    assert loaded["statics"].dtype == np.float32


def test_scaler_uses_only_target_dates_and_expected_ddof(tmp_path):
    import json

    case, root = build_synthetic_case(tmp_path)
    forcing = np.load(root / "forcing.npy", allow_pickle=False)
    targets = np.load(root / "targets.npy", allow_pickle=False)
    raw = np.load(root / "statics_raw.float64.npy", allow_pickle=False)
    scaler = json.loads((root / "scaler.json").read_text(encoding="utf-8"))
    np.testing.assert_allclose(scaler["dynamic_center_float64"], forcing[:, 2:5, :].mean(axis=(0, 1), dtype=np.float64))
    assert scaler["target_scale_float64"] == targets.astype(np.float64).std(ddof=0)
    np.testing.assert_allclose(scaler["static_scale_float64"], raw.std(axis=0, ddof=1))


def test_synthetic_builder_refuses_any_path_in_formal_result_tree(tmp_path):
    from formal_input_contract_v09 import WORKTREE_ROOT, primary_repository_root_v09
    from formal_input_v09 import build_synthetic_input_seal_v09

    case = make_synthetic_input_case(tmp_path)
    forbidden = WORKTREE_ROOT / "results/26_historical_band_experts/formal_v09/synthetic-forbidden"
    with pytest.raises(ValueError, match="authorized runtime"):
        build_synthetic_input_seal_v09(**case, building_root=forbidden)
    assert not forbidden.exists()
    other_formal = primary_repository_root_v09() / "results/26_historical_band_experts/formal_v09/synthetic-forbidden"
    with pytest.raises(ValueError, match="temporary directory"):
        build_synthetic_input_seal_v09(**case, building_root=other_formal)
    assert not other_formal.exists()


def test_builder_never_overwrites_existing_directory(tmp_path):
    from formal_input_v09 import build_synthetic_input_seal_v09

    case = make_synthetic_input_case(tmp_path)
    root = tmp_path / "existing"
    root.mkdir()
    with pytest.raises(FileExistsError):
        build_synthetic_input_seal_v09(**case, building_root=root)
