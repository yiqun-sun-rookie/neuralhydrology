"""Track definitions. Each track is a separated, independently-rigorous contest.

A track bundles: the frozen baseline NSE vector, the held observation answer
key, the secret-holdout basin set, the gate thresholds, and the information
budget (allow_observed_q). Adding a track = adding a spec.yaml + frozen files;
the scoring spine does not change. Cross-track comparison is forbidden — that
firewall lives in the leaderboard, keyed by track name.

The spec.yaml (`<name>.spec.yaml`) is the single source of truth: it lists the
frozen file locations, the gate thresholds, and a `confirmed` flag that a human
sets to true after checking every field. `load_track` CONSUMES that spec — it
refuses to build a Track from an unconfirmed spec and derives the gate config
from it, so the contract is enforced, not just documented.

  track0_forcing_only : allow_observed_q=False, baseline = LSTM 8-seed ens.
  track1_past_q       : (future) allow_observed_q=True up to issue time t0,
                        rolling-origin eval; reuses src/ylx_dl_da guards.
"""
from dataclasses import dataclass, field
from pathlib import Path

import pandas as pd
from ruamel.yaml import YAML

from .gate import GateConfig

_REPO_ROOT = Path(__file__).resolve().parents[2]  # src/fair_benchmark/tracks.py -> repo root
_yaml = YAML(typ="safe")


class TrackNotConfirmedError(RuntimeError):
    """Raised when a track's spec.yaml has not been human-confirmed (confirmed: false)."""


@dataclass
class Track:
    name: str
    baseline_nse: dict          # basin -> NSE (frozen)
    obs: dict                   # basin -> pd.Series (the held answer key)
    secret_holdout: set         # basin ids scored only for the consistency check
    gate_cfg: GateConfig = field(default_factory=GateConfig)
    allow_observed_q: bool = False
    forbidden_patterns: list = None  # None -> leakage.DEFAULT_FORBIDDEN (Track 1 drops obs-Q)
    metric: object = None            # metric(obs, sim)->float; None -> authoritative NSE (higher=better)
    spec: dict = None                # the raw spec.yaml contract (provenance), or None


def _read_baseline_csv(path) -> dict:
    df = pd.read_csv(path, dtype={"basin": str})
    return {str(b): float(v) for b, v in zip(df["basin"], df["NSE"])}


def _read_holdout(path) -> set:
    text = Path(path).read_text(encoding="utf-8")
    return {line.strip() for line in text.splitlines() if line.strip()}


def _read_spec(path):
    path = Path(path)
    if not path.exists():
        return None
    with path.open("r", encoding="utf-8") as f:
        return _yaml.load(f)


def _resolve(ref, frozen_dir) -> Path:
    """Resolve a spec-declared file reference: try it repo-root-relative first
    (the spec uses repo-relative paths), then fall back to its basename inside
    frozen_dir — robust to copied/moved frozen sets and test tmpdirs."""
    cand = _REPO_ROOT / str(ref)
    if cand.exists():
        return cand
    return Path(frozen_dir) / Path(str(ref)).name


def _gate_cfg_from_spec(spec) -> GateConfig:
    """Build the GateConfig from the spec: metric.min_meaningful_effect sets the
    minimum effect, and an optional `gate:` block overrides any field."""
    if not spec:
        return GateConfig()
    kwargs = {}
    metric = spec.get("metric") or {}
    if metric.get("min_meaningful_effect") is not None:
        kwargs["min_effect"] = float(metric["min_meaningful_effect"])
    gate = spec.get("gate") or {}
    for key in ("min_effect", "max_wilcoxon_p", "holdout_min_effect", "holdout_retention"):
        if key in gate:
            kwargs[key] = float(gate[key])
    return GateConfig(**kwargs)


def load_track(name: str, frozen_dir, allow_observed_q: bool = False,
               require_confirmed: bool = True) -> Track:
    """Build a Track from its spec.yaml contract under frozen_dir/<name>.spec.yaml.

    The spec lists the frozen files (baseline_nse_vector, secret_holdout_file,
    answer_key_held) and the gate thresholds, and carries a `confirmed` flag.

    Raises TrackNotConfirmedError if the spec exists with confirmed != true and
    require_confirmed is True (the default). Pass require_confirmed=False (or the
    CLI's --allow-unconfirmed) for cheap exploration against an unratified spec.

    Falls back to the historical naming convention + default GateConfig when no
    spec.yaml is present.
    """
    from .io import load_obs_csv  # local import to avoid cycle at module load

    frozen = Path(frozen_dir)
    spec = _read_spec(frozen / f"{name}.spec.yaml")

    if spec is not None:
        if require_confirmed and not bool(spec.get("confirmed", False)):
            raise TrackNotConfirmedError(
                f"Track '{name}' spec is not human-confirmed (confirmed: false). "
                f"Review {frozen / f'{name}.spec.yaml'} and set confirmed: true, "
                f"or pass require_confirmed=False / --allow-unconfirmed to explore.")
        baseline_path = _resolve(spec.get("baseline_nse_vector",
                                          f"{name}_baseline_per_basin_nse.csv"), frozen)
        holdout_path = _resolve(spec.get("secret_holdout_file",
                                         f"{name}_secret_holdout_basins.txt"), frozen)
        obs_path = _resolve(spec.get("answer_key_held", f"{name}_obs_eval.parquet"), frozen)
        gate_cfg = _gate_cfg_from_spec(spec)
    else:
        baseline_path = frozen / f"{name}_baseline_per_basin_nse.csv"
        holdout_path = frozen / f"{name}_secret_holdout_basins.txt"
        obs_path = frozen / f"{name}_obs_eval.parquet"
        gate_cfg = GateConfig()

    baseline = _read_baseline_csv(baseline_path)
    obs = load_obs_csv(obs_path) if Path(obs_path).exists() else {}
    holdout = _read_holdout(holdout_path)
    return Track(name=name, baseline_nse=baseline, obs=obs, secret_holdout=holdout,
                 gate_cfg=gate_cfg, allow_observed_q=allow_observed_q, spec=spec)
