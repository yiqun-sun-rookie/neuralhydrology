from collections import OrderedDict

from src.xaj_global_pilot.structures import (
    build_gr4j_pdd_structure,
    build_gr4j_structure,
    build_xaj_pdd_structure,
    build_xaj_structure,
)
# NOTE: "hbv" model removed 2026-06-05 (old hbv_camels_us_531 SuperflexPy HBV archived,
# superseded by scl_hydro/hbv_lite). See src/scl_hydro/README_HBV_MODELS.md.


def get_model_specs() -> OrderedDict:
    return OrderedDict(
        [
            (
                "primary",
                OrderedDict(
                    [
                        (
                            "xaj_pdd",
                            {
                                "uses_snow_module": True,
                                "parameter_count": 20,
                                "solver_name": "explicit_euler",
                                "family": "xaj",
                                "structure_builder": build_xaj_pdd_structure,
                            },
                        ),
                        (
                            "gr4j_pdd",
                            {
                                "uses_snow_module": True,
                                "parameter_count": 10,
                                "solver_name": "implicit_euler",
                                "family": "gr4j",
                                "structure_builder": build_gr4j_pdd_structure,
                            },
                        ),
                    ]
                ),
            ),
            (
                "ablations",
                OrderedDict(
                    [
                        (
                            "xaj",
                            {
                                "uses_snow_module": False,
                                "parameter_count": 14,
                                "solver_name": "explicit_euler",
                                "family": "xaj",
                                "structure_builder": build_xaj_structure,
                            },
                        ),
                        (
                            "gr4j",
                            {
                                "uses_snow_module": False,
                                "parameter_count": 4,
                                "solver_name": "implicit_euler",
                                "family": "gr4j",
                                "structure_builder": build_gr4j_structure,
                            },
                        ),
                    ]
                ),
            ),
        ]
    )
