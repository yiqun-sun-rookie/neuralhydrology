from collections import OrderedDict

from src.xaj_global_pilot.structures import (
    build_gr4j_pdd_structure,
    build_gr4j_structure,
    build_hbv_structure,
    build_xaj_pdd_structure,
    build_xaj_structure,
)


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
                            "hbv",
                            {
                                "uses_snow_module": True,
                                "parameter_count": 12,
                                "solver_name": "implicit_euler",
                                "family": "hbv",
                                "structure_builder": build_hbv_structure,
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
