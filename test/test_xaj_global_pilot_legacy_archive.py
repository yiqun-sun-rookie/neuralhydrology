import importlib
from pathlib import Path


LEGACY_SCRIPT_MODULES = (
    "src.xaj_global_pilot.scripts.run_xaj_global_pilot",
    "src.xaj_global_pilot.scripts.run_full_comparison",
    "src.xaj_global_pilot.scripts.run_hbv_baseline",
    "src.xaj_global_pilot.scripts.run_ablation_et",
    "src.xaj_global_pilot.scripts.run_ablation_runoff",
)


def test_legacy_scripts_expose_redirect_message():
    for module_name in LEGACY_SCRIPT_MODULES:
        module = importlib.import_module(module_name)
        assert hasattr(module, "LEGACY_MESSAGE")
        assert "archive_legacy" in module.LEGACY_MESSAGE
        assert "run_conceptual_screening" in module.LEGACY_MESSAGE


def test_xaj_global_pilot_readmes_explain_active_and_archived_workflows():
    active_readme = Path("src/xaj_global_pilot/README.md").read_text(encoding="utf-8")
    archive_readme = Path("src/xaj_global_pilot/archive_legacy/README.md").read_text(encoding="utf-8")

    assert "CAMELS-US" in active_readme
    assert "run_conceptual_screening.py" in active_readme
    assert "legacy" in archive_readme.lower()
    assert "Caravan" in archive_readme
