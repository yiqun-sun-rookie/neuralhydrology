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
from datetime import datetime
from pathlib import Path

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))

from hydroagent.agent import (
    HydroAgent,
    OpenAIClient,
    OllamaClient,
    DeepSeekClient,
    ClaudeClient,
    MockLLMClient
)
from hydroagent.data_loading import load_camels_basin
from hydroagent.experiment_logger import ExperimentLogger


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
            model = args.model or 'claude-opus-4-8'
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
    
    # Create experiment logger
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    exp_dir = Path(f"results/07_hydroagent/{args.basin}_{args.backend}_{timestamp}")
    logger = ExperimentLogger(exp_dir, args.basin, args.backend, target_nse=0.6, max_iterations=args.max_iter)
    print(f"\n[3] Experiment log: {exp_dir}")

    # Create agent
    agent = HydroAgent(llm_client=client, max_iterations=args.max_iter, logger=logger)

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
    print(f"\nResults saved to: {exp_dir}")

    return result


if __name__ == '__main__':
    main()

