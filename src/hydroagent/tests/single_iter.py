"""Single iteration test - run one structure and get diagnostics"""
import os
import sys
import json
import numpy as np
import pandas as pd

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))

from hydroagent.environment import SuperflexEnv
from hydroagent.diagnosis import HydroDiagnostician


def load_data():
    data_root = r'G:\github\pycharm\projects\neuralhydrology\data\camels_us'
    basin_id = '01022500'
    huc = basin_id[:2]
    
    forcing_path = os.path.join(data_root, 'basin_mean_forcing', 'daymet', huc, basin_id + '_lump_cida_forcing_leap.txt')
    df_forcing = pd.read_csv(forcing_path, skiprows=3, sep=r'\s+')
    df_forcing['date'] = pd.to_datetime(df_forcing[['Year', 'Mnth', 'Day']].rename(columns={'Year': 'year', 'Mnth': 'month', 'Day': 'day'}))
    df_forcing.set_index('date', inplace=True)
    
    streamflow_path = os.path.join(data_root, 'usgs_streamflow', huc, basin_id + '_streamflow_qc.txt')
    df_sf = pd.read_csv(streamflow_path, sep=r'\s+', header=None, names=['gauge_id', 'year', 'month', 'day', 'discharge_cfs', 'qc_flag'])
    df_sf['date'] = pd.to_datetime(df_sf[['year', 'month', 'day']])
    df_sf.set_index('date', inplace=True)
    
    start_date, end_date = '1990-10-01', '1993-09-30'
    forcing = df_forcing.loc[start_date:end_date].copy()
    streamflow = df_sf.loc[start_date:end_date].copy()
    
    topo_file = os.path.join(data_root, 'camels_attributes_v2.0', 'camels_topo.txt')
    df_topo = pd.read_csv(topo_file, sep=';')
    df_topo['gauge_id'] = df_topo['gauge_id'].astype(str).str.zfill(8)
    area_km2 = df_topo[df_topo['gauge_id'] == basin_id]['area_gages2'].values[0]
    
    streamflow['qobs_mm'] = streamflow['discharge_cfs'] * 2.4466 / area_km2
    streamflow.loc[streamflow['discharge_cfs'] < 0, 'qobs_mm'] = np.nan
    
    forcing_out = pd.DataFrame(index=forcing.index)
    forcing_out['prcp'] = forcing['prcp(mm/day)'].values
    tmax, tmin, srad = forcing['tmax(C)'].values, forcing['tmin(C)'].values, forcing['srad(W/m2)'].values
    pet = 0.0023 * (srad * 0.0864) * np.sqrt(np.maximum(tmax - tmin, 0.1)) * ((tmax + tmin) / 2 + 17.8)
    forcing_out['ep'] = np.maximum(pet, 0)
    
    common_idx = forcing_out.index.intersection(streamflow.index)
    forcing_out = forcing_out.loc[common_idx]
    obs = streamflow.loc[common_idx, 'qobs_mm']
    valid_mask = ~obs.isna()
    
    return forcing_out.loc[valid_mask], obs.loc[valid_mask]


def run_structure(structure_json):
    """Run a structure and return results"""
    forcing, obs = load_data()
    
    if isinstance(structure_json, str):
        structure = json.loads(structure_json)
    else:
        structure = structure_json
    
    env = SuperflexEnv()
    env.parse_structure(structure)
    result = env.auto_calibrate(forcing, obs)
    
    diag = HydroDiagnostician()
    report = diag.generate_report(obs, result['qsim'])
    
    return result['nse'], result.get('optimized_params', {}), report


if __name__ == '__main__':
    # Get structure from command line or use default
    if len(sys.argv) > 1:
        structure = json.loads(sys.argv[1])
    else:
        structure = {
            "model_name": "initial_v0",
            "layers": [
                {"id": "soil", "type": "UnsaturatedReservoir", "parameters": ["Smax", "beta"], "inputs": ["prcp", "ep"]},
                {"id": "fast", "type": "PowerReservoir", "parameters": ["k", "alpha"], "inputs": ["soil.runoff"]}
            ],
            "lag_functions": [],
            "system_output": ["fast"]
        }
    
    print("Running structure: %s" % structure.get('model_name', 'unknown'))
    nse, params, report = run_structure(structure)
    
    print("\n=== RESULTS ===")
    print("NSE: %.4f" % nse)
    print("KGE: %.4f" % report['metrics'].get('KGE', -999))
    print("Peak Lag: %.1f hours" % report['metrics'].get('Peak_Lag_Hours', 0))
    print("Low Flow Bias: %.1f%%" % (report['metrics'].get('Low_Flow_Bias', 0) * 100))
    print("\nParameters:", params)
    print("\nFeedback:")
    for fb in report['semantic_feedback']:
        print("  -", fb)

