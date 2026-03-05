"""Batch experiment runner for HydroAgent.

Runs a basins x backends matrix of experiments, collecting results into summary.csv.

Usage:
    # Single basin, mock backend (smoke test)
    python src/hydroagent/scripts/run_batch.py --basins 01022500 --backends mock --max-iter 2

    # Phase 2 preset with mock
    python src/hydroagent/scripts/run_batch.py --basins phase2 --backends mock --max-iter 4

    # Multi-backend matrix
    python src/hydroagent/scripts/run_batch.py --basins phase2 --backends mock,deepseek --max-iter 4
"""
from __future__ import annotations

import argparse
import csv
import os
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

# Ensure hydroagent is importable when running from project root
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))

from hydroagent.agent import (
    HydroAgent,
    BaseLLMClient,
    OpenAIClient,
    OllamaClient,
    DeepSeekClient,
    ClaudeClient,
    MockLLMClient,
    RandomLLMClient,
)
from hydroagent.data_loading import load_camels_basin
from hydroagent.diagnosis import HydroDiagnostician
from hydroagent.experiment_logger import ExperimentLogger

# ---------------------------------------------------------------------------
# Basin presets
# ---------------------------------------------------------------------------

BASIN_PRESETS = {
    'phase2': ['01022500', '01013500', '08013000', '07014500'],
    'benchmark': ['01022500', '01547700', '02064000', '03015500', '01169000', '04056500'],
    'paper': [
        # 东部湿润（6 existing benchmark）
        '01022500',  # Maine, snow=0.25, arid=0.59, 574km2
        '01547700',  # Pennsylvania, 114km2
        '02064000',  # Virginia, 428km2
        '03015500',  # NY/PA, 785km2
        '01169000',  # Massachusetts, 231km2
        '04056500',  # Michigan, 2946km2
        # 积雪主导（3 basins）
        '11264500',  # Sierra Nevada, snow=0.91, arid=1.15, 468km2 [HUCdir=18]
        '06623800',  # Wyoming, snow=0.75, arid=1.06, 188km2
        '07083000',  # Colorado Rockies, snow=0.71, elev=3457m, 61km2
        # 干旱/半干旱（3 basins）
        '10259200',  # SoCal/Mojave, snow=0.00, arid=4.76, 79km2 [HUCdir=18]
        '09447800',  # Arizona, snow=0.04, arid=3.04, 782km2 [HUCdir=15]
        '08271000',  # New Mexico, snow=0.48, arid=2.38, 44km2
        # 湿润亚热带（1）
        '02177000',  # South Carolina, snow=0.03, arid=0.52, 527km2
        # 中西部（1）
        '05393500',  # Wisconsin, snow=0.20, arid=0.87, 220km2
        # 大流域（1）
        '06452000',  # Missouri/Great Plains, arid=1.74, 25791km2 [HUCdir=10]
        # 太平洋西北（1）
        '12010000',  # Washington, snow=0.02, arid=0.25, 142km2 [HUCdir=17]
        # 大盆地/高山（1）
        '10348850',  # Great Basin/NV, snow=0.83, arid=1.18, 19km2 [HUCdir=16]
        # 太平洋北部山地（1）
        '13313000',  # Idaho, snow=0.74, arid=0.79, 562km2 [HUCdir=17]
    ],
}

# ---------------------------------------------------------------------------
# Ablation configurations
# ---------------------------------------------------------------------------

ABLATION_CONFIGS = {
    'full':            {'enabled_groups': None,  'strip_feedback': False, 'backend_override': None},
    'no_feedback':     {'enabled_groups': None,  'strip_feedback': True,  'backend_override': None},
    'no_cross_domain': {'enabled_groups': ['hydro_basic', 'peak_timing', 'flow_regime', 'seasonal'],
                        'strip_feedback': False, 'backend_override': None},
    'no_seasonal':     {'enabled_groups': ['hydro_basic', 'peak_timing', 'flow_regime', 'cross_domain'],
                        'strip_feedback': False, 'backend_override': None},
    'random':          {'enabled_groups': [],    'strip_feedback': False, 'backend_override': 'random'},
}

# ---------------------------------------------------------------------------
# LLM client factory
# ---------------------------------------------------------------------------


def create_llm_client(
    backend: str,
    api_key: Optional[str] = None,
    model: Optional[str] = None,
) -> BaseLLMClient:
    """Create an LLM client from a backend name string."""
    if backend == 'mock':
        return MockLLMClient()
    elif backend == 'openai':
        return OpenAIClient(api_key=api_key, model=model or 'gpt-4o-mini')
    elif backend == 'deepseek':
        return DeepSeekClient(api_key=api_key, model=model or 'deepseek-chat')
    elif backend == 'claude':
        return ClaudeClient(api_key=api_key, model=model or 'claude-opus-4-6')
    elif backend == 'ollama':
        return OllamaClient(model=model or 'llama3.2')
    elif backend == 'random':
        return RandomLLMClient(seed=42)
    else:
        raise ValueError(f"Unknown backend: {backend}")


# ---------------------------------------------------------------------------
# Single experiment runner
# ---------------------------------------------------------------------------


def run_single_experiment(
    basin_id: str,
    backend: str,
    forcing,
    obs,
    output_dir: Path,
    max_iter: int = 4,
    target_nse: float = 0.6,
    api_key: Optional[str] = None,
    model: Optional[str] = None,
    ablation: Optional[str] = None,
) -> Dict[str, Any]:
    """Run one (basin, backend) experiment. Returns a summary row dict.

    Wrapped in try/except so failures don't kill the batch.
    """
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    ablation_tag = ablation or 'default'
    exp_dir = output_dir / f"{basin_id}_{backend}_{ablation_tag}_{timestamp}"

    summary = {
        'basin_id': basin_id,
        'backend': backend,
        'ablation': ablation or '',
        'best_nse': None,
        'converged': False,
        'total_iterations': 0,
        'model_name': '',
        'duration_s': 0.0,
        'experiment_dir': str(exp_dir),
        'error': '',
    }

    # Resolve ablation config
    abl_cfg = ABLATION_CONFIGS.get(ablation, ABLATION_CONFIGS['full']) if ablation else {}
    enabled_groups = abl_cfg.get('enabled_groups')
    strip_feedback = abl_cfg.get('strip_feedback', False)
    backend_override = abl_cfg.get('backend_override')

    effective_backend = backend_override or backend

    t_start = time.time()
    try:
        client = create_llm_client(effective_backend, api_key=api_key, model=model)
        logger = ExperimentLogger(exp_dir, basin_id, effective_backend,
                                  target_nse=target_nse, max_iterations=max_iter,
                                  ablation_variant=ablation)
        agent = HydroAgent(llm_client=client, max_iterations=max_iter, logger=logger)

        # Ablation: custom diagnostician with filtered metric groups
        if ablation:
            doctor = HydroDiagnostician(enabled_groups=enabled_groups)
            if strip_feedback:
                _orig_report = doctor.generate_report
                def _stripped_report(o, s, _orig=_orig_report):
                    result = _orig(o, s)
                    result['semantic_feedback'] = []
                    return result
                doctor.generate_report = _stripped_report
            agent.doctor = doctor

        result = agent.solve(forcing, obs, target_nse=target_nse)

        summary['best_nse'] = round(result['best_nse'], 4)
        summary['converged'] = result['best_nse'] >= target_nse
        summary['total_iterations'] = len(agent.history)
        if result['best_structure']:
            summary['model_name'] = result['best_structure'].get('model_name', '')
    except Exception as e:
        summary['error'] = str(e)
        print(f"  [ERROR] {basin_id} x {backend}: {e}")

    summary['duration_s'] = round(time.time() - t_start, 1)
    return summary


# ---------------------------------------------------------------------------
# Summary output
# ---------------------------------------------------------------------------

SUMMARY_FIELDS = [
    'basin_id', 'backend', 'ablation', 'best_nse', 'converged', 'total_iterations',
    'model_name', 'duration_s', 'experiment_dir', 'error',
]


def write_summary(summaries: List[Dict[str, Any]], output_dir: Path) -> Path:
    """Write summary.csv and print an ASCII table."""
    csv_path = output_dir / 'summary.csv'
    output_dir.mkdir(parents=True, exist_ok=True)

    with open(csv_path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=SUMMARY_FIELDS)
        writer.writeheader()
        for row in summaries:
            writer.writerow(row)

    # ASCII table
    print("\n" + "=" * 90)
    print("BATCH SUMMARY")
    print("=" * 90)
    header = f"{'Basin':<12} {'Backend':<10} {'NSE':>8} {'Conv':>5} {'Iter':>5} {'Model':<25} {'Time':>7}"
    print(header)
    print("-" * 90)
    for row in summaries:
        nse_str = f"{row['best_nse']:.4f}" if row['best_nse'] is not None else 'FAIL'
        conv_str = 'Y' if row['converged'] else 'N'
        model_str = (row['model_name'] or '')[:25]
        print(f"{row['basin_id']:<12} {row['backend']:<10} {nse_str:>8} {conv_str:>5} "
              f"{row['total_iterations']:>5} {model_str:<25} {row['duration_s']:>6.1f}s")

    if summaries:
        valid_nses = [r['best_nse'] for r in summaries if r['best_nse'] is not None]
        n_converged = sum(1 for r in summaries if r['converged'])
        n_errors = sum(1 for r in summaries if r['error'])
        print("-" * 90)
        if valid_nses:
            print(f"Mean NSE: {sum(valid_nses)/len(valid_nses):.4f}  |  "
                  f"Converged: {n_converged}/{len(summaries)}  |  "
                  f"Errors: {n_errors}/{len(summaries)}")
        else:
            print(f"No valid results.  Errors: {n_errors}/{len(summaries)}")

    print(f"\nSummary CSV: {csv_path}")
    return csv_path


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def resolve_basins(basins_arg: str) -> List[str]:
    """Resolve a basins argument to a list of basin IDs.

    Accepts either a preset name (e.g. 'phase2') or comma-separated IDs.
    """
    if basins_arg in BASIN_PRESETS:
        return BASIN_PRESETS[basins_arg]
    return [b.strip() for b in basins_arg.split(',') if b.strip()]


def main():
    parser = argparse.ArgumentParser(
        description='HydroAgent batch experiment runner',
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument('--basins', type=str, required=True,
                        help='Comma-separated basin IDs, or preset name: phase2, benchmark')
    parser.add_argument('--backends', type=str, default='mock',
                        help='Comma-separated backends: mock,deepseek,openai,claude,ollama (default: mock)')
    parser.add_argument('--max-iter', type=int, default=4,
                        help='Max iterations per experiment (default: 4)')
    parser.add_argument('--target-nse', type=float, default=0.6,
                        help='NSE convergence threshold (default: 0.6)')
    parser.add_argument('--output-dir', type=str, default='results/07_hydroagent',
                        help='Output root directory (default: results/07_hydroagent)')
    parser.add_argument('--api-key', type=str, default=None,
                        help='API key (for OpenAI/DeepSeek/Claude)')
    parser.add_argument('--model', type=str, default=None,
                        help='Model name override')
    parser.add_argument('--data-root', type=str, default=None,
                        help='CAMELS-US data root (default: auto-detect)')
    parser.add_argument('--ablation', type=str, default=None,
                        choices=list(ABLATION_CONFIGS.keys()),
                        help='Ablation variant (default: None = full pipeline)')

    args = parser.parse_args()

    basins = resolve_basins(args.basins)
    backends = [b.strip() for b in args.backends.split(',') if b.strip()]
    output_dir = Path(args.output_dir)

    print("=" * 60)
    print("HydroAgent Batch Runner")
    print("=" * 60)
    print(f"Basins ({len(basins)}):   {', '.join(basins)}")
    print(f"Backends ({len(backends)}): {', '.join(backends)}")
    print(f"Ablation:    {args.ablation or '(none)'}")
    print(f"Max iter:    {args.max_iter}")
    print(f"Target NSE:  {args.target_nse}")
    print(f"Output:      {output_dir}")
    print(f"Total experiments: {len(basins) * len(backends)}")

    # Phase 1: Load data (cache per basin)
    print("\n[Phase 1] Loading basin data...")
    basin_data = {}
    for basin_id in basins:
        try:
            forcing, obs, area = load_camels_basin(basin_id, data_root=args.data_root)
            basin_data[basin_id] = (forcing, obs, area)
            print(f"  {basin_id}: {len(forcing)} days, area={area:.1f} km2")
        except Exception as e:
            print(f"  {basin_id}: LOAD FAILED - {e}")

    if not basin_data:
        print("\nNo basins loaded successfully. Exiting.")
        return

    # Phase 2: Run experiments
    print(f"\n[Phase 2] Running {len(basin_data) * len(backends)} experiments...")
    summaries: List[Dict[str, Any]] = []
    exp_idx = 0
    total = len(basin_data) * len(backends)

    for basin_id in basins:
        if basin_id not in basin_data:
            continue
        forcing, obs, _area = basin_data[basin_id]

        for backend in backends:
            exp_idx += 1
            print(f"\n--- Experiment {exp_idx}/{total}: {basin_id} x {backend} ---")
            row = run_single_experiment(
                basin_id=basin_id,
                backend=backend,
                forcing=forcing,
                obs=obs,
                output_dir=output_dir,
                max_iter=args.max_iter,
                target_nse=args.target_nse,
                api_key=args.api_key,
                model=args.model,
                ablation=args.ablation,
            )
            summaries.append(row)
            nse_str = f"{row['best_nse']:.4f}" if row['best_nse'] is not None else 'FAIL'
            print(f"  Result: NSE={nse_str}, converged={row['converged']}, "
                  f"iters={row['total_iterations']}, time={row['duration_s']}s")

    # Phase 3: Summary
    write_summary(summaries, output_dir)


if __name__ == '__main__':
    main()
