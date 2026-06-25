# Design Spec — HydroAgent as a Claude Code Skill (`hydro-discover`)

- **Date**: 2026-06-25
- **Status**: Design approved (brainstorming) → pending spec review → writing-plans
- **Idea**: 07 (HydroAgent / agentic structure discovery)
- **Related**: `src/hydroagent/{agent.py,environment.py,diagnosis.py,data_loading.py}`,
  `src/hydroagent/scripts/run_batch.py`, memory `hydroagent-identifiability-session-20260619`

## 1. Motivation

HydroAgent's Module C (the "brain" that reads a diagnosis and designs/refines a
conceptual rainfall-runoff structure) is currently driven by an LLM backend —
in practice DeepSeek, which is too weak. Concrete evidence from the 2026-06-24
post-bugfix rerun: basin `08271000` ran the full 12 refinement iterations under
DeepSeek and only reached **NSE 0.0131** (diagnosis: "fails to capture the
snow-driven regime, high winter bias"). A stronger brain should do better.

The goal is to let **Claude Code CLI's Claude (Opus 4.8)** be Module C, invoked
directly by the user as a skill, replacing DeepSeek for interactive discovery —
using the subscription model (strongest reasoning, no per-call API cost).

The environment (calibration + 24-metric diagnosis + 14-component library) is
already backend-agnostic and separable in code, so swapping the brain is clean.

## 2. Goals / Non-goals

**Goals**
- Interactive structure discovery in CC CLI, with Claude as the design/refine brain.
- Reuse existing `SuperflexEnv` (calibration) and `HydroDiagnostician` (diagnosis)
  verbatim — no duplicated science, inherits the 2026-06-24 crash bug fixes.
- Dual data protocol via one switch: fast in-sample (exploration) and
  `repro_v01` (paper-comparable out-of-sample).
- Full per-session logging so a discovery run is traceable and a discovered
  structure can later be re-scored / re-run under a reproducible backend.
- Keep a clean seam so the **Claude API automated backend** (reproducible paper
  path) plugs in later with minimal work.

**Non-goals (YAGNI)**
- No MCP server (CLI core stays reusable if we ever want to wrap one).
- No new automated multi-basin batch driver for the skill (run_batch already
  covers automated/reproducible backends).
- No new components or diagnosis metrics.
- No removal of the existing DeepSeek/Claude API backends.

## 3. Key decisions (with rationale)

| # | Decision | Choice | Why |
|---|----------|--------|-----|
| D1 | Primary purpose | Tool first, feed back to paper | User wants better discovery now; keep repro path open |
| D2 | Mechanism | **Skill + thin CLI** (not MCP) | Zero server lifecycle; fits the `forecast_system_lite` conda-env constraint; simplest |
| D3 | Loop granularity | **Single-step evaluator** | CLI exposes `evaluate`; Claude owns loop/stop/rollback/branch — actually uses the strong model's agentic ability |
| D4 | Data protocol | **Dual, `--protocol` switch** | Fast in-sample for iteration; `repro_v01` for paper-comparable scoring |
| D5 | Later automation | **Claude API automated backend** | Reproducible paper path = existing `ClaudeClient` + run_batch; share env primitives + heuristics |

## 4. Architecture

```
Claude (CC CLI, the brain) ── via the hydro-discover skill
   │  1. reads component vocabulary + JSON schema   (hydro_cli components)
   │  2. reads basin climate/attributes             (hydro_cli basin-info)
   │  3. writes structure_NN.json, evaluates it     (hydro_cli evaluate)
   ▼
hydro_cli.py   (run with forecast_system_lite python via Bash)
   │  SuperflexEnv.parse_structure + auto_calibrate  → NSE, params, qsim
   │  HydroDiagnostician.generate_report             → 24 metrics + semantic feedback
   ▼  prints clean JSON to stdout (warnings → stderr) + appends history.jsonl
Claude reads JSON → reasons about what's wrong → next structure_NN+1.json → evaluate …
   (loop / best-tracking / stop / rollback all controlled by Claude)
```

`hydro_cli.py` is a **thin adapter**: it imports and calls the existing
`SuperflexEnv`, `HydroDiagnostician`, `load_camels_basin`, `load_basin_metadata`.
It does not reimplement calibration or diagnosis.

## 5. CLI contract — `src/hydroagent/scripts/hydro_cli.py`

Single CLI, argparse subcommands. Run via
`PYTHONPATH=src <forecast_system_lite python> src/hydroagent/scripts/hydro_cli.py <cmd> …`.

### 5.1 `components`
Prints the component library and structure schema as JSON:
- For each component (14 reservoir/flux types + base elements): `type` name,
  calibratable params with `(lo, hi)` bounds, default values, input conventions
  (`prcp`/`ep`/`temperature`/`<id>.<output>`), and which are root vs downstream.
- The structure JSON schema (`model_name`, `layers[]`, `lag_functions[]`,
  `system_output[]`) plus one minimal valid example.
Derived programmatically from `_REGISTRY` / `_BASEELEM_REGISTRY` / `_LAG_REGISTRY`
in `environment.py` so it never drifts from the actual code.

### 5.2 `basin-info <basin_id> [--protocol fast|repro_v01]`
Prints basin metadata as JSON: area, climate/aridity/snow attributes (via
`load_basin_metadata`), forcing days available, and the resolved protocol's
calib/eval windows. Helps Claude pick a starting structure and read the diagnosis.

### 5.3 `evaluate <basin_id> --structure <path.json> [--protocol fast|repro_v01] [--trials N] [--out <dir>]`
The core. Steps: validate → calibrate → diagnose → emit JSON + append history.

**Output JSON (stdout, the only thing on stdout):**
```json
{
  "valid": true,
  "basin_id": "08271000",
  "protocol": "fast",
  "model_name": "HBV_light_v3",
  "nse": 0.41,            // calibration-period (or in-sample) NSE
  "eval_nse": null,       // out-of-sample NSE when protocol=repro_v01, else null
  "n_params": 11,
  "params": { "...": 0.0 },
  "diagnosis": {
    "metrics": { "NSE": 0.41, "KGE": 0.33, "Snow_Season_NSE": -1.2, "...": 0.0 },
    "semantic_feedback": ["High winter bias …", "Recession too fast …"]
  },
  "qsim_path": "results/07_hydroagent/cc_discover/08271000_<ts>/qsim_003.csv",
  "history_path": "results/07_hydroagent/cc_discover/08271000_<ts>/history.jsonl",
  "warnings": [],
  "errors": []
}
```
**Invalid-structure JSON** (no calibration run):
```json
{ "valid": false, "errors": ["Unknown component type 'FooStore' in layer 'soil'",
  "layer 'routing' input 'prod.runoff' references undefined id 'prod'"], "...": null }
```

**Exit codes**: `0` = structure valid and evaluated (even if NSE is poor or -999);
`2` = structure invalid (validated, not calibrated); `1` = unexpected internal error.

`--trials` overrides CMA-ES `n_trials` (default 2000; e.g. 500 for a ~40s quick
pass). `--out` sets/continues the session dir (default a timestamped dir).

## 6. The skill — `.claude/skills/hydro-discover/SKILL.md`

`.claude/skills/` does not exist yet; create it. Skill teaches Claude the loop:

1. **Load vocabulary**: run `components`; treat its schema as the source of truth.
2. **Read the basin**: run `basin-info <id>`; note climate (snow/arid/area).
3. **Propose initial structure**: write `structure_001.json`, `evaluate` it.
4. **Diagnose & refine**: read `nse` + `diagnosis.semantic_feedback`; reason about
   the specific failure (snow regime, baseflow recession, peak timing, FDC slope)
   → write a refined structure → `evaluate`. Repeat.
5. **Explore topology, not just templates**: actively try series/parallel/cascade,
   under-used components, and non-parallel topologies — carry over the v12 lesson
   that the agent over-uses the `soil→fast+slow` parallel template. Keep a running
   best; the best is always retained so exploration is safe.
6. **Stop**: when target NSE reached, or N iterations without improvement, or Claude
   judges diminishing returns. Claude decides (no Python early-stop).
7. **Finalize**: re-`evaluate` the best structure under `--protocol repro_v01` to
   report out-of-sample NSE; compare against baselines (LSTM 0.759, GR4J 0.653,
   XAJ 0.620, HBV 0.617). Report the best structure JSON + history path.

The skill's refinement guidance is kept **consistent with** the prompt heuristics
in `agent.py` (`STRUCTURE_PROMPT`/`DIAGNOSTICIAN_PROMPT`) so interactive and
automated-backend behavior are comparable (see §8).

## 7. Dual protocol

| protocol | forcing | PET | period | NSE reported | use |
|----------|---------|-----|--------|--------------|-----|
| `fast` (default) | daymet | oudin | single in-sample window (v12-style, ~3 yr) | calibration-period | fast exploration (~2-3 min, or ~40 s at `--trials 500`) |
| `repro_v01` | maurer_extended | priestley-taylor (α=1.26) | calib + held-out eval (eval 1989-1999) | **out-of-sample** `eval_nse` | paper-comparable, slower |

Implemented as a small protocol→config map feeding existing
`load_camels_basin(forcing=…, pet_method=…, start_date=…, end_date=…)` args.
`evaluate` under `repro_v01` calibrates on the calib window and forward-runs the
best params on the eval window (mirrors `run_batch.py` split-mode post-hoc eval).
Exact `pet_method` token and the `repro_v01` date windows to be confirmed against
`data_loading.py` / the repro_v01 protocol doc during implementation.

## 8. Error handling & clean-output contract

- **Validation before calibration**: unknown component, missing/empty required
  field, input referencing an undefined id, or empty `layers` → `{valid:false,
  errors:[specific, human-readable]}`, exit 2. This directly fixes the v12
  failure mode where an invalid init structure silently fell back to a default
  (`"Unknown component type: None, using default"`) — now it is an explicit,
  actionable error Claude can self-correct from.
- **Calibration crash** → already contained by the 2026-06-24 fixes (ValueError
  caught at element solve, crash penalty `1e6`, finite-guard → -999). `evaluate`
  returns a finite NSE, or `nse:-999` with a note in `warnings`.
- **Clean stdout**: `evaluate` prints **only** the JSON result to stdout. All
  SuperflexPy numerical noise (the `[ind]` lambdified-expression spam, RuntimeWarnings,
  numdifftools output) is routed to stderr / a log file. Non-negotiable: Claude
  must receive parseable JSON, not 190 KB of solver spam (observed on 2026-06-24).

## 9. Claude API automated backend seam (reproducible paper path)

This path mostly **already exists** (`ClaudeClient` in `agent.py:815` + run_batch's
`--backends claude`). Spec work here is to verify and tidy, not rebuild:
- Update the stale default model id `claude-opus-4-6` → current (`claude-opus-4-8`).
- Confirm `run_batch --backends claude` runs end-to-end with `ANTHROPIC_API_KEY`.
- Ensure prompts + seed + raw responses are logged for reproducibility
  (`experiment_logger` already writes `llm_responses.jsonl`; verify completeness).
- Keep the skill's discovery heuristics (§6) aligned with `STRUCTURE_PROMPT` /
  `DIAGNOSTICIAN_PROMPT` so interactive (skill) and automated (Claude API) paths
  produce comparable structures.
- Both paths share the same env primitives and (after this work) the same
  component/schema source of truth (§5.1).

Result: the **structure** is the artifact, decoupled from which brain found it.
Interactive Claude finds candidates fast; the Claude API backend reproduces an
automated run for the paper.

## 10. Logging, session layout, paper bridge

Session dir: `results/07_hydroagent/cc_discover/<basin>_<timestamp>/` containing
`structure_NNN.json`, `qsim_NNN.csv`, and an appended `history.jsonl`
(one record per evaluate: structure, protocol, nse/eval_nse, params, key metrics).
Mirrors the existing `experiment_logger` record shape so downstream analysis and
identifiability tooling can read both. A discovery session therefore yields:
best structure JSON, its `repro_v01` out-of-sample NSE, and the full trace.

## 11. Testing

Runnable smoke scripts (not pytest — pytest collects only `test/`), in the style
of `src/hydroagent/scripts/_offline_bugfix_check.py`:
1. `evaluate` a known-good structure (e.g. HBV-light parallel) on one basin under
   `--protocol fast` → assert `valid:true`, finite `nse`, well-formed JSON.
2. `evaluate` an invalid structure (unknown component) → assert `valid:false`,
   specific error, exit 2.
3. `components` output parses as JSON and lists the known component types.
4. One `--protocol repro_v01` evaluate on a basin → asserts `eval_nse` present and
   finite (sanity that the split path works).

## 12. Honesty caveat (paper framing) — carry into any write-up

Structures found by **interactive** Claude are not themselves an "automated
reproducible discovery." For a paper the honest framing is "Claude-assisted
discovery of candidate structures, then reproducible evaluation," or treating the
discovered structures as an oracle / upper bound. This is consistent with the
de-risk conclusion ("don't sell the LLM as the contribution") and does not
conflict with the pending A/B strategic decision — but write-ups must not
over-claim automated discovery.

## 13. Open items to confirm during implementation

- Exact `pet_method` token for Priestley-Taylor in `data_loading.load_camels_basin`.
- `repro_v01` calib/eval date windows and `forcing` value (`maurer` vs
  `maurer_extended`) — align to the repro_v01 protocol doc.
- CC project skill discovery: confirm `.claude/skills/<name>/SKILL.md` is picked up
  in this repo's CC config.
- Current Claude model id string accepted by `ClaudeClient`.
```
