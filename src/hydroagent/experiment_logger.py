"""Structured experiment logging for HydroAgent.

Writes four files per experiment:
- meta.json        — experiment-level metadata (written once, updated at end)
- iterations.csv   — one row per iteration with scalar metrics
- structures.jsonl  — one JSON line per iteration with full structure + params
- llm_responses.jsonl — one JSON line per LLM call with prompt preview + response
"""
from __future__ import annotations

import csv
import json
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Optional


class ExperimentLogger:
    """Records HydroAgent experiment data to structured files."""

    def __init__(self, output_dir: Path, basin_id: str, backend: str,
                 target_nse: float, max_iterations: int,
                 ablation_variant: Optional[str] = None):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)

        self.meta_path = self.output_dir / 'meta.json'
        self.csv_path = self.output_dir / 'iterations.csv'
        self.structures_path = self.output_dir / 'structures.jsonl'
        self.llm_path = self.output_dir / 'llm_responses.jsonl'

        self._csv_writer: Optional[csv.DictWriter] = None
        self._csv_file = None

        # Write initial meta
        self._start_time = datetime.now()
        experiment_id = f"{basin_id}_{backend}_{self._start_time.strftime('%Y%m%d_%H%M%S')}"
        self._meta = {
            'experiment_id': experiment_id,
            'basin_id': basin_id,
            'llm_backend': backend,
            'ablation_variant': ablation_variant,
            'target_nse': target_nse,
            'max_iterations': max_iterations,
            'start_time': self._start_time.isoformat(timespec='seconds'),
            'end_time': None,
            'best_nse': None,
            'total_iterations': 0,
            'converged': False,
        }
        self._write_meta()

    def log_iteration(self, iteration: int, structure: dict,
                      cal_result: Dict[str, Any], report: dict,
                      duration_s: float):
        """Append one row to iterations.csv and one line to structures.jsonl."""
        metrics = report.get('metrics', {})

        # -- CSV row --
        row = {'iteration': iteration}
        row['model_name'] = structure.get('model_name', '')
        row['num_layers'] = len(structure.get('layers', []))
        # Flatten all scalar metrics
        for k, v in metrics.items():
            row[k] = v
        row['duration_s'] = round(duration_s, 2)

        if self._csv_writer is None:
            self._csv_file = open(self.csv_path, 'w', newline='', encoding='utf-8')
            self._csv_writer = csv.DictWriter(self._csv_file, fieldnames=list(row.keys()))
            self._csv_writer.writeheader()
        self._csv_writer.writerow(row)
        self._csv_file.flush()

        # -- structures.jsonl --
        record = {
            'iteration': iteration,
            'structure': structure,
            'params': cal_result.get('optimized_params', {}),
        }
        with open(self.structures_path, 'a', encoding='utf-8') as f:
            f.write(json.dumps(record, ensure_ascii=False) + '\n')

    def log_llm_response(self, iteration: int, prompt: str,
                         response_text: str, parsed_ok: bool):
        """Append one line to llm_responses.jsonl."""
        record = {
            'iteration': iteration,
            'prompt_preview': prompt[:500],
            'response_text': response_text,
            'parsed_ok': parsed_ok,
        }
        with open(self.llm_path, 'a', encoding='utf-8') as f:
            f.write(json.dumps(record, ensure_ascii=False) + '\n')

    def finalize(self, best_nse: float, total_iterations: int, converged: bool):
        """Update meta.json with end_time and final results."""
        self._meta['end_time'] = datetime.now().isoformat(timespec='seconds')
        self._meta['best_nse'] = best_nse
        self._meta['total_iterations'] = total_iterations
        self._meta['converged'] = converged
        self._write_meta()

        if self._csv_file is not None:
            self._csv_file.close()
            self._csv_file = None
            self._csv_writer = None

    def _write_meta(self):
        with open(self.meta_path, 'w', encoding='utf-8') as f:
            json.dump(self._meta, f, indent=2, ensure_ascii=False)
