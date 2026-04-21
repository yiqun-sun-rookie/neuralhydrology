from src.xaj_global_pilot.model_catalog import get_model_specs


def test_model_catalog_splits_primary_models_and_ablations():
    specs = get_model_specs()
    assert tuple(specs["primary"].keys()) == ("xaj_pdd", "hbv", "gr4j_pdd")
    assert tuple(specs["ablations"].keys()) == ("xaj", "gr4j")

    for group_name in ("primary", "ablations"):
        for spec in specs[group_name].values():
            assert "uses_snow_module" in spec
            assert "parameter_count" in spec
            assert "solver_name" in spec
            assert "family" in spec
            assert "structure_builder" in spec

    assert all(spec["uses_snow_module"] is True for spec in specs["primary"].values())
    assert all(spec["uses_snow_module"] is False for spec in specs["ablations"].values())
