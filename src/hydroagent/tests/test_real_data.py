import os
import sys
import numpy as np
import pandas as pd

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../../..')))

from hydroagent.environment import SuperflexEnv
from hydroagent.diagnosis import HydroDiagnostician


def load_camels_basin(basin_id, data_root, start_date='1990-10-01', end_date='1995-09-30'):
    """Load CAMELS-US basin data"""
    huc = basin_id[:2]
    
    # Load forcing
    forcing_path = os.path.join(
        data_root, 'basin_mean_forcing', 'daymet', huc,
        basin_id + '_lump_cida_forcing_leap.txt'
    )
    
    if not os.path.exists(forcing_path):
        raise FileNotFoundError("Forcing file not found: " + forcing_path)
    
    df_forcing = pd.read_csv(forcing_path, skiprows=3, sep=r'\s+')
    
    df_forcing['date'] = pd.to_datetime(
        df_forcing[['Year', 'Mnth', 'Day']].rename(
            columns={'Year': 'year', 'Mnth': 'month', 'Day': 'day'}
        )
    )
    df_forcing.set_index('date', inplace=True)
    
    # Load streamflow
    streamflow_path = os.path.join(
        data_root, 'usgs_streamflow', huc,
        basin_id + '_streamflow_qc.txt'
    )
    
    df_sf = pd.read_csv(
        streamflow_path, sep=r'\s+', header=None,
        names=['gauge_id', 'year', 'month', 'day', 'discharge_cfs', 'qc_flag']
    )
    
    df_sf['date'] = pd.to_datetime(df_sf[['year', 'month', 'day']])
    df_sf.set_index('date', inplace=True)
    
    forcing = df_forcing.loc[start_date:end_date].copy()
    streamflow = df_sf.loc[start_date:end_date].copy()
    
    # Get area from attributes file (more reliable)
    topo_file = os.path.join(data_root, 'camels_attributes_v2.0', 'camels_topo.txt')
    df_topo = pd.read_csv(topo_file, sep=';')
    df_topo['gauge_id'] = df_topo['gauge_id'].astype(str).str.zfill(8)
    area_km2 = df_topo[df_topo['gauge_id'] == basin_id]['area_gages2'].values[0]
    
    # Convert cfs to mm/day
    conversion_factor = 2.4466 / area_km2
    streamflow['qobs_mm'] = streamflow['discharge_cfs'] * conversion_factor
    streamflow.loc[streamflow['discharge_cfs'] < 0, 'qobs_mm'] = np.nan
    
    forcing_out = pd.DataFrame(index=forcing.index)
    forcing_out['prcp'] = forcing['prcp(mm/day)'].values
    
    # Estimate PET using simplified Hargreaves
    tmax = forcing['tmax(C)'].values
    tmin = forcing['tmin(C)'].values
    srad = forcing['srad(W/m2)'].values
    tmean = (tmax + tmin) / 2
    delta_t = np.maximum(tmax - tmin, 0.1)
    pet = 0.0023 * (srad * 0.0864) * np.sqrt(delta_t) * (tmean + 17.8)
    pet = np.maximum(pet, 0)
    forcing_out['ep'] = pet
    
    # Align and clean
    common_idx = forcing_out.index.intersection(streamflow.index)
    forcing_out = forcing_out.loc[common_idx]
    obs = streamflow.loc[common_idx, 'qobs_mm']
    
    valid_mask = ~obs.isna()
    forcing_out = forcing_out.loc[valid_mask]
    obs = obs.loc[valid_mask]
    
    print("Basin %s: Area=%.1f km2, Records=%d" % (basin_id, area_km2, len(forcing_out)))
    print("  Mean P=%.2f, PET=%.2f, Q=%.2f mm/d" % (forcing_out['prcp'].mean(), forcing_out['ep'].mean(), obs.mean()))
    
    return forcing_out, obs


def test_with_real_data():
    """Test HydroAgent with real CAMELS data"""
    data_root = r'G:\github\pycharm\projects\neuralhydrology\data\camels_us'
    basin_id = '01022500'
    
    print("=" * 60)
    print("HydroAgent Real Data Test")
    print("=" * 60)
    
    print("\n[1] Loading CAMELS data...")
    forcing, obs = load_camels_basin(basin_id, data_root, '1990-10-01', '1993-09-30')
    
    print("\n[2] Building model...")
    structure = {
        'model_name': 'camels_test_v1',
        'layers': [
            {'id': 'soil', 'type': 'UnsaturatedReservoir', 'parameters': ['Smax', 'beta'], 'inputs': ['prcp', 'ep']},
            {'id': 'fast', 'type': 'PowerReservoir', 'parameters': ['k', 'alpha'], 'inputs': ['soil.runoff']}
        ],
        'lag_functions': [],
        'system_output': ['fast']
    }
    
    env = SuperflexEnv()
    env.parse_structure(structure)
    
    print("\n[3] Initial simulation...")
    q_sim_init = env.run_simulation(forcing)
    
    diag = HydroDiagnostician()
    report_init = diag.generate_report(obs, q_sim_init)
    print("  Initial NSE: %.4f" % report_init['metrics']['NSE'])
    
    print("\n[4] Calibrating parameters...")
    result = env.auto_calibrate(forcing, obs)
    
    nse_final = result['nse']
    params = result.get('optimized_params', {})
    q_sim_cal = result['qsim']
    
    print("  Calibrated NSE: %.4f" % nse_final)
    print("  Parameters:", params)
    
    print("\n[5] Final diagnostics...")
    report_final = diag.generate_report(obs, q_sim_cal)
    print("  KGE: %.4f" % report_final['metrics']['KGE'])
    
    print("\n  Semantic Feedback:")
    for fb in report_final['semantic_feedback']:
        print("    - " + fb)
    
    print("\n" + "=" * 60)
    print("Summary")
    print("=" * 60)
    print("  Basin: %s" % basin_id)
    print("  Days: %d" % len(forcing))
    print("  Initial NSE: %.4f" % report_init['metrics']['NSE'])
    print("  Final NSE: %.4f" % nse_final)
    
    if nse_final > 0.5:
        print("\n  [PASS] Model works on real data!")
    else:
        print("\n  [WARN] NSE < 0.5, model may need structure adjustment.")
    
    return result


if __name__ == '__main__':
    test_with_real_data()

