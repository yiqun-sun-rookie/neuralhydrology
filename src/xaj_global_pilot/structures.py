from src.hbv_camels_us_531.structure import build_fixed_hbv_structure


def build_xaj_structure() -> dict:
    lag_config = [{"type": "HalfTriangularLag", "target": "fast", "lag_steps": 2.0}]
    return {
        "model_name": "xaj_global_pilot_xaj",
        "layers": [
            {
                "id": "soil",
                "type": "UpperZone",
                "parameters": ["Smax", "m", "beta"],
                "inputs": ["prcp", "ep"],
                "outputs": ["runoff"],
            },
            {
                "id": "fast",
                "type": "PowerReservoir",
                "parameters": ["k", "alpha"],
                "inputs": ["soil.runoff"],
                "outputs": ["q_fast"],
            },
            {
                "id": "slow",
                "type": "LinearReservoir",
                "parameters": ["k"],
                "inputs": ["soil.runoff"],
                "outputs": ["q_slow"],
            },
        ],
        "lag_functions": lag_config,
        "system_output": ["fast", "slow"],
    }


def build_xaj_pdd_structure() -> dict:
    lag_config = [{"type": "HalfTriangularLag", "target": "fast", "lag_steps": 2.0}]
    return {
        "model_name": "xaj_global_pilot_xaj_pdd",
        "layers": [
            {
                "id": "snow",
                "type": "SnowReservoir",
                "parameters": ["t0", "k", "m"],
                "inputs": ["prcp", "tmean"],
                "outputs": ["outflow"],
            },
            {
                "id": "soil",
                "type": "UpperZone",
                "parameters": ["Smax", "m", "beta"],
                "inputs": ["snow.outflow", "ep"],
                "outputs": ["runoff"],
            },
            {
                "id": "fast",
                "type": "PowerReservoir",
                "parameters": ["k", "alpha"],
                "inputs": ["soil.runoff"],
                "outputs": ["q_fast"],
            },
            {
                "id": "slow",
                "type": "LinearReservoir",
                "parameters": ["k"],
                "inputs": ["soil.runoff"],
                "outputs": ["q_slow"],
            },
        ],
        "lag_functions": lag_config,
        "system_output": ["fast", "slow"],
    }


def build_hbv_structure() -> dict:
    return build_fixed_hbv_structure()


def build_gr4j_structure() -> dict:
    return {
        "model_name": "xaj_global_pilot_gr4j",
        "layers": [
            {
                "id": "interception",
                "type": "InterceptionFilter",
                "inputs": ["ep", "prcp"],
                "outputs": ["throughfall"],
            },
            {
                "id": "production",
                "type": "ProductionStore",
                "inputs": ["ep", "interception.out_flux"],
                "outputs": ["out_flux"],
            },
            {
                "id": "routing",
                "type": "RoutingStore",
                "inputs": ["production.out_flux"],
                "outputs": ["qsim"],
            },
        ],
        "lag_functions": [
            {
                "type": "UnitHydrograph1",
                "target": "routing",
                "lag_steps": 3.5,
            }
        ],
        "system_output": ["routing"],
    }


def build_gr4j_pdd_structure() -> dict:
    return {
        "model_name": "xaj_global_pilot_gr4j_pdd",
        "layers": [
            {
                "id": "snow",
                "type": "SnowReservoir",
                "parameters": ["t0", "k", "m"],
                "inputs": ["prcp", "tmean"],
                "outputs": ["out_flux"],
            },
            {
                "id": "interception",
                "type": "InterceptionFilter",
                "inputs": ["ep", "snow.out_flux"],
                "outputs": ["throughfall"],
            },
            {
                "id": "production",
                "type": "ProductionStore",
                "inputs": ["ep", "interception.out_flux"],
                "outputs": ["out_flux"],
            },
            {
                "id": "routing",
                "type": "RoutingStore",
                "inputs": ["production.out_flux"],
                "outputs": ["qsim"],
            },
        ],
        "lag_functions": [
            {
                "type": "UnitHydrograph1",
                "target": "routing",
                "lag_steps": 3.5,
            }
        ],
        "system_output": ["routing"],
    }
