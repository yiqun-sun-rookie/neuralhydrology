"""
Interactive HydroAgent Test - Use Claude (me!) directly in conversation

Usage:
1. Run this script
2. Copy the diagnostic output 
3. Paste to Claude in conversation
4. Claude will return improved structure JSON
5. Paste the JSON back when prompted
6. Repeat until satisfied
"""

import os
import sys
import json
import numpy as np
import pandas as pd

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../../..')))

from hydroagent.environment import SuperflexEnv
from hydroagent.diagnosis import HydroDiagnostician


def load_camels_basin(basin_id, data_root, start_date='1990-10-01', end_date='1993-09-30'):
    """Load CAMELS-US basin data"""
    huc = basin_id[:2]
    
    forcing_path = os.path.join(
        data_root, 'basin_mean_forcing', 'daymet', huc,
        basin_id + '_lump_cida_forcing_leap.txt'
    )
    
    df_forcing = pd.read_csv(forcing_path, skiprows=3, sep=r'\s+')
    df_forcing['date'] = pd.to_datetime(
        df_forcing[['Year', 'Mnth', 'Day']].rename(
            columns={'Year': 'year', 'Mnth': 'month', 'Day': 'day'}
        )
    )
    df_forcing.set_index('date', inplace=True)
    
    streamflow_path = os.path.join(
        data_root, 'usgs_streamflow', huc,
        basin_id + '_streamflow_qc.txt'
    )
    
    df_sf = pd.read_csv(streamflow_path, sep=r'\s+', header=None,
        names=['gauge_id', 'year', 'month', 'day', 'discharge_cfs', 'qc_flag'])
    df_sf['date'] = pd.to_datetime(df_sf[['year', 'month', 'day']])
    df_sf.set_index('date', inplace=True)
    
    forcing = df_forcing.loc[start_date:end_date].copy()
    streamflow = df_sf.loc[start_date:end_date].copy()
    
    topo_file = os.path.join(data_root, 'camels_attributes_v2.0', 'camels_topo.txt')
    df_topo = pd.read_csv(topo_file, sep=';')
    df_topo['gauge_id'] = df_topo['gauge_id'].astype(str).str.zfill(8)
    area_km2 = df_topo[df_topo['gauge_id'] == basin_id]['area_gages2'].values[0]
    
    conversion_factor = 2.4466 / area_km2
    streamflow['qobs_mm'] = streamflow['discharge_cfs'] * conversion_factor
    streamflow.loc[streamflow['discharge_cfs'] < 0, 'qobs_mm'] = np.nan
    
    forcing_out = pd.DataFrame(index=forcing.index)
    forcing_out['prcp'] = forcing['prcp(mm/day)'].values
    
    tmax = forcing['tmax(C)'].values
    tmin = forcing['tmin(C)'].values
    srad = forcing['srad(W/m2)'].values
    tmean = (tmax + tmin) / 2
    delta_t = np.maximum(tmax - tmin, 0.1)
    pet = 0.0023 * (srad * 0.0864) * np.sqrt(delta_t) * (tmean + 17.8)
    forcing_out['ep'] = np.maximum(pet, 0)
    
    common_idx = forcing_out.index.intersection(streamflow.index)
    forcing_out = forcing_out.loc[common_idx]
    obs = streamflow.loc[common_idx, 'qobs_mm']
    valid_mask = ~obs.isna()
    forcing_out = forcing_out.loc[valid_mask]
    obs = obs.loc[valid_mask]
    
    return forcing_out, obs


def run_iteration(structure, forcing, obs):
    """Run one iteration: build, calibrate, diagnose"""
    env = SuperflexEnv()
    env.parse_structure(structure)
    result = env.auto_calibrate(forcing, obs)
    
    q_sim = result['qsim']
    nse = result['nse']
    params = result.get('optimized_params', {})
    
    diag = HydroDiagnostician()
    report = diag.generate_report(obs, q_sim)
    
    return nse, params, report


def format_prompt_for_claude(structure, report):
    """Format the prompt to send to Claude"""
    prompt = """
## Current Model Structure
```json
%s
```

## Performance
- NSE: %.4f
- KGE: %.4f  
- Peak Lag: %.1f hours
- Peak MAPE: %.1f%%
- Low Flow Bias: %.1f%%

## Diagnostic Feedback
%s

## Available Components
1. UnsaturatedReservoir - soil moisture, params: Smax, beta, inputs: prcp, ep
2. PowerReservoir - fast/nonlinear flow, params: k, alpha
3. LinearReservoir - slow/baseflow, params: k

## Task
Please provide an IMPROVED model structure JSON to increase NSE.
Return ONLY the JSON, no explanation.
""" % (
        json.dumps(structure, indent=2),
        report['metrics'].get('NSE', -999),
        report['metrics'].get('KGE', -999),
        report['metrics'].get('Peak_Lag_Hours', 0),
        report['metrics'].get('Peak_MAPE', 0) * 100,
        report['metrics'].get('Low_Flow_Bias', 0) * 100,
        '\n'.join(['- ' + fb for fb in report['semantic_feedback']])
    )
    return prompt


def main():
    data_root = r'G:\github\pycharm\projects\neuralhydrology\data\camels_us'
    basin_id = '01022500'
    
    print("=" * 60)
    print("Interactive HydroAgent Test")
    print("=" * 60)
    
    print("\n[1] Loading data...")
    forcing, obs = load_camels_basin(basin_id, data_root)
    print("    Basin: %s, Days: %d" % (basin_id, len(forcing)))
    
    # Initial structure
    current_structure = {
        "model_name": "initial_v0",
        "layers": [
            {"id": "soil", "type": "UnsaturatedReservoir", "parameters": ["Smax", "beta"], "inputs": ["prcp", "ep"]},
            {"id": "fast", "type": "PowerReservoir", "parameters": ["k", "alpha"], "inputs": ["soil.runoff"]}
        ],
        "lag_functions": [],
        "system_output": ["fast"]
    }
    
    best_nse = -999
    best_structure = None
    iteration = 0
    
    while True:
        iteration += 1
        print("\n" + "=" * 60)
        print("ITERATION %d" % iteration)
        print("=" * 60)
        
        print("\n[2] Running model: %s" % current_structure['model_name'])
        try:
            nse, params, report = run_iteration(current_structure, forcing, obs)
        except Exception as e:
            print("ERROR: %s" % e)
            print("Please fix the structure and try again.")
            continue
        
        print("\n[3] Results:")
        print("    NSE: %.4f" % nse)
        print("    KGE: %.4f" % report['metrics'].get('KGE', -999))
        print("    Parameters: %s" % params)
        
        if nse > best_nse:
            best_nse = nse
            best_structure = current_structure.copy()
            print("    *** NEW BEST! ***")
        
        print("\n[4] Diagnostic Feedback:")
        for fb in report['semantic_feedback']:
            print("    - %s" % fb)
        
        if nse >= 0.6:
            print("\n*** TARGET NSE (0.6) REACHED! ***")
            break
        
        # Generate prompt for Claude
        print("\n" + "=" * 60)
        print("COPY THE FOLLOWING TO CLAUDE:")
        print("=" * 60)
        prompt = format_prompt_for_claude(current_structure, report)
        print(prompt)
        print("=" * 60)
        
        # Get response from user (Claude's answer)
        print("\nPaste Claude's JSON response (or 'quit' to exit):")
        print(">>> ", end="")
        
        lines = []
        while True:
            try:
                line = input()
                if line.strip().lower() == 'quit':
                    print("\nExiting...")
                    break
                lines.append(line)
                # Check if we have complete JSON
                text = '\n'.join(lines)
                if text.strip().startswith('{') and text.strip().endswith('}'):
                    try:
                        new_structure = json.loads(text)
                        if 'layers' in new_structure:
                            current_structure = new_structure
                            print("\n[OK] Structure updated: %s" % new_structure.get('model_name', 'unknown'))
                            break
                    except json.JSONDecodeError:
                        pass  # Keep reading
            except EOFError:
                break
        
        if line.strip().lower() == 'quit':
            break
    
    print("\n" + "=" * 60)
    print("FINAL RESULTS")
    print("=" * 60)
    print("Best NSE: %.4f" % best_nse)
    print("Best Structure: %s" % json.dumps(best_structure, indent=2))


if __name__ == '__main__':
    main()

