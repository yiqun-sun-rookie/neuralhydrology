"""
Test HydroAgent with LLM integration on real CAMELS data.

Usage:
    # With Ollama (local, free)
    python test_agent_llm.py --backend ollama --model llama3.2
    
    # With DeepSeek (cheaper alternative)
    python test_agent_llm.py --backend deepseek --api-key YOUR_KEY
    
    # With OpenAI
    python test_agent_llm.py --backend openai --api-key YOUR_KEY --model gpt-4o-mini
"""

import os
import sys
import argparse
import numpy as np
import pandas as pd

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../../..')))

from hydroagent.agent import (
    HydroAgent, 
    OpenAIClient, 
    OllamaClient, 
    DeepSeekClient,
    ClaudeClient,
    MockLLMClient
)


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
    
    # Get area
    topo_file = os.path.join(data_root, 'camels_attributes_v2.0', 'camels_topo.txt')
    df_topo = pd.read_csv(topo_file, sep=';')
    df_topo['gauge_id'] = df_topo['gauge_id'].astype(str).str.zfill(8)
    area_km2 = df_topo[df_topo['gauge_id'] == basin_id]['area_gages2'].values[0]
    
    # Convert cfs to mm/day
    conversion_factor = 2.4466 / area_km2
    streamflow['qobs_mm'] = streamflow['discharge_cfs'] * conversion_factor
    streamflow.loc[streamflow['discharge_cfs'] < 0, 'qobs_mm'] = np.nan
    
    # Prepare forcing
    forcing_out = pd.DataFrame(index=forcing.index)
    forcing_out['prcp'] = forcing['prcp(mm/day)'].values
    
    # Estimate PET
    tmax = forcing['tmax(C)'].values
    tmin = forcing['tmin(C)'].values
    srad = forcing['srad(W/m2)'].values
    tmean = (tmax + tmin) / 2
    delta_t = np.maximum(tmax - tmin, 0.1)
    pet = 0.0023 * (srad * 0.0864) * np.sqrt(delta_t) * (tmean + 17.8)
    forcing_out['ep'] = np.maximum(pet, 0)
    
    # Align
    common_idx = forcing_out.index.intersection(streamflow.index)
    forcing_out = forcing_out.loc[common_idx]
    obs = streamflow.loc[common_idx, 'qobs_mm']
    valid_mask = ~obs.isna()
    forcing_out = forcing_out.loc[valid_mask]
    obs = obs.loc[valid_mask]
    
    return forcing_out, obs, area_km2


def main():
    parser = argparse.ArgumentParser(description='Test HydroAgent with LLM')
    parser.add_argument('--backend', type=str, default='mock',
                        choices=['openai', 'ollama', 'deepseek', 'claude', 'mock'],
                        help='LLM backend to use (default: mock for testing)')
    parser.add_argument('--model', type=str, default=None,
                        help='Model name (default depends on backend)')
    parser.add_argument('--api-key', type=str, default=None,
                        help='API key for OpenAI/DeepSeek')
    parser.add_argument('--basin', type=str, default='01022500',
                        help='CAMELS basin ID')
    parser.add_argument('--max-iter', type=int, default=4,
                        help='Maximum iterations')
    
    args = parser.parse_args()
    
    # Data path
    data_root = r'G:\github\pycharm\projects\neuralhydrology\data\camels_us'
    
    print("=" * 60)
    print("HydroAgent LLM Integration Test")
    print("=" * 60)
    print("Backend: %s" % args.backend)
    print("Basin: %s" % args.basin)
    print("Max Iterations: %d" % args.max_iter)
    
    # Load data
    print("\n[1] Loading CAMELS data...")
    forcing, obs, area = load_camels_basin(args.basin, data_root)
    print("    Records: %d days" % len(forcing))
    print("    Area: %.1f km2" % area)
    
    # Create LLM client
    print("\n[2] Initializing LLM client...")
    try:
        if args.backend == 'openai':
            model = args.model or 'gpt-4o-mini'
            client = OpenAIClient(api_key=args.api_key, model=model)
            print("    Using OpenAI: %s" % model)
        elif args.backend == 'deepseek':
            client = DeepSeekClient(api_key=args.api_key)
            print("    Using DeepSeek")
        elif args.backend == 'claude':
            model = args.model or 'claude-sonnet-4-20250514'
            client = ClaudeClient(api_key=args.api_key, model=model)
            print("    Using Claude: %s" % model)
        elif args.backend == 'mock':
            client = MockLLMClient()
            print("    Using Mock LLM (rule-based structure improvements)")
        else:  # ollama
            model = args.model or 'llama3.2'
            client = OllamaClient(model=model)
            print("    Using Ollama: %s" % model)
    except Exception as e:
        print("    ERROR: %s" % e)
        print("\n    Falling back to Mock LLM mode")
        client = MockLLMClient()
    
    # Create agent
    print("\n[3] Creating HydroAgent...")
    agent = HydroAgent(llm_client=client, max_iterations=args.max_iter)
    
    # Run optimization
    print("\n[4] Starting optimization loop...\n")
    result = agent.solve(forcing, obs, target_nse=0.6)
    
    # Results
    print("\n" + "=" * 60)
    print("FINAL RESULTS")
    print("=" * 60)
    print("Best NSE: %.4f" % result['best_nse'])
    print("Best Structure:")
    if result['best_structure']:
        import json
        print(json.dumps(result['best_structure'], indent=2))
    print("\nOptimized Parameters:")
    print(result['best_params'])
    
    return result


if __name__ == '__main__':
    main()

