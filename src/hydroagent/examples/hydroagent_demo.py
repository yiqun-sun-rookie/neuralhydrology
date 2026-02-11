import pandas as pd
import numpy as np
import json
import matplotlib.pyplot as plt
from hydroagent import SuperflexEnv, HydroDiagnostician

def generate_synthetic_data(n_steps=500):
    dates = pd.date_range(start="2024-01-01", periods=n_steps, freq="H")
    prcp = np.zeros(n_steps)
    indices = np.arange(0, n_steps, 24)
    prcp[indices] = 5.0 + np.random.rand(len(indices)) * 5 
    t = np.linspace(0, 4*np.pi, n_steps)
    ep = 0.5 + 0.3 * np.sin(t)
    obs = np.convolve(prcp, np.ones(5)/5.0, mode="same") * 0.8
    obs += 0.5 
    obs += np.random.normal(0, 0.05, n_steps)
    obs = np.maximum(obs, 0)
    forcing = pd.DataFrame({"prcp": prcp, "ep": ep}, index=dates)
    obs_series = pd.Series(obs, index=dates, name="qobs")
    return forcing, obs_series

def main():
    print(">>> 1. Generating Synthetic Data...")
    forcing, obs = generate_synthetic_data()
    print(f"Data generated: {len(forcing)} steps")
    
    print("\n>>> 2. Defining Model Structure (JSON)...")
    structure = {
        "model_name": "test_model_v1",
        "layers": [
            {
                "id": "res1",
                "type": "UnsaturatedReservoir",
                "parameters": ["Smax", "beta", "Ce"], 
                "inputs": ["prcp", "ep"],
                "outputs": ["out_flux"] 
            },
            {
                "id": "res2",
                "type": "LinearReservoir",
                "parameters": ["k"],
                "inputs": ["res1.out_flux"],
                "outputs": ["out_flux"]
            }
        ],
        "lag_functions": [],
        "system_output": ["res2"]
    }
    
    print("\n>>> 3. Initializing Environment (Module B)...")
    env = SuperflexEnv()
    
    print(">>> 4. Parsing Structure & Building Network...")
    env.parse_structure(structure)
    
    print("\n>>> 5. Running Simulation (Before Calibration)...")
    try:
        q_init = env.run_simulation(forcing)
        print("Initial simulation successful.")
    except Exception as e:
        print(f"Simulation failed: {e}")
        return

    print("\n>>> 6. Auto-Calibrating...")
    try:
        result = env.auto_calibrate(forcing, obs)
        print("Calibration Result:")
        # Use get just in case
        print(f"Optimized NSE: {result.get('nse', -999):.4f}")
        q_final = result.get('qsim')
    except Exception as e:
        print(f"Calibration Error: {e}")
        q_final = None

    if q_final is None:
        print("Using initial sim for diagnosis due to calibration failure.")
        q_final = q_init
        
    print("\n>>> 7. Diagnostics (Module A)...")
    diagnostician = HydroDiagnostician(cfg={'window_hours': 12})
    report = diagnostician.generate_report(obs, q_final)
    
    print("-" * 30)
    print("DIAGNOSTIC REPORT")
    print("-" * 30)
    print(json.dumps(report, indent=2, ensure_ascii=False))

if __name__ == "__main__":
    main()

