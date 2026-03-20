def build_fixed_hbv_structure() -> dict:
    lag_config = [
        {
            "type": "HalfTriangularLag",
            "target": "fast",
            "lag_steps": 2.0,
        }
    ]
    return {
        "model_name": "hbv_camels_us_531_fixed_v1",
        "layers": [
            {
                "id": "snow",
                "type": "SnowReservoir",
                "parameters": ["t0", "k", "m"],
                "inputs": ["prcp", "tmean"],
                "outputs": ["out_flux"],
            },
            {
                "id": "soil",
                "type": "UnsaturatedReservoir",
                "parameters": ["Smax", "Ce", "m", "beta"],
                "inputs": ["snow.out_flux", "ep"],
                "outputs": ["out_flux"],
            },
            {
                "id": "fast",
                "type": "PowerReservoir",
                "parameters": ["k", "alpha"],
                "inputs": ["soil.out_flux"],
                "outputs": ["q_fast"],
            },
            {
                "id": "slow",
                "type": "LinearReservoir",
                "parameters": ["k"],
                "inputs": ["soil.out_flux"],
                "outputs": ["q_slow"],
            },
        ],
        "lags": lag_config,
        "lag_functions": lag_config,
        "system_output": ["fast", "slow"],
    }
