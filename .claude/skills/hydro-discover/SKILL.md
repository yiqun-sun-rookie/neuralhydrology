---
name: hydro-discover
description: Use when discovering or improving a conceptual rainfall-runoff (hydrological) model STRUCTURE for a CAMELS-US basin — when the user wants Claude to act as the model-design brain (proposing/refining SuperflexPy component graphs) instead of the weak DeepSeek backend. Triggers: "discover a structure for basin X", "improve the HydroAgent model", "what conceptual model fits this basin".
---

# hydro-discover — Claude as the HydroAgent structure-design brain

You design conceptual rainfall-runoff model structures; a thin CLI calibrates and
diagnoses them. You own the loop. Run every command with the project's env python
from the project root:

    PYEXE="C:/Users/yiqun/anaconda3/envs/forecast_system_lite/python.exe"
    CLI="src/hydroagent/scripts/hydro_cli.py"

## Loop

1. **Load the vocabulary** — `"$PYEXE" "$CLI" components`. The JSON lists every
   component `type`, its parameter `bounds`, `input_map`, the structure `schema`,
   and a valid `example`. This is the source of truth — only use listed types.
2. **Read the basin** — `"$PYEXE" "$CLI" basin-info <basin_id> --protocol fast`.
   Note area, aridity, snow fraction; let climate guide the starting structure
   (e.g. snow component for snowy basins).
3. **Propose** — write `structure_001.json` (follow the schema; `parameters: {}`
   uses calibrated defaults). Evaluate:
   `"$PYEXE" "$CLI" evaluate <basin_id> --structure structure_001.json --protocol fast --trials 1000`
4. **Read the result JSON** — `nse` plus `diagnosis.semantic_feedback` and
   `diagnosis.metrics` (snow-season NSE, winter bias, recession, FDC slope, peak
   timing). Diagnose the SPECIFIC failure, don't guess.
5. **Refine** — write `structure_002.json` addressing the diagnosed failure, then
   evaluate. Repeat. Keep a running best; the CLI never discards your structures.
6. **Explore topology, not templates** — actively try series, cascade, and
   under-used components. The known failure mode (v12) is over-using the
   `soil → fast + slow` parallel template. Vary topology deliberately.
7. **Stop** when NSE plateaus (no improvement over ~3 refinements), a good target
   is reached, or returns diminish. YOU decide — there is no automatic stop.
8. **Finalize** — re-evaluate the best structure under `--protocol repro_v01`
   (out-of-sample). Report the best structure JSON, its `eval_nse`, and compare to
   baselines: LSTM 0.759, GR4J 0.653, XAJ 0.620, HBV 0.617.

## Rules

- Use `--protocol fast` while iterating (cheap); `--protocol repro_v01` only to
  finalize (out-of-sample, paper-comparable).
- A `valid:false` result (exit 2) means the structure is malformed — read
  `errors`, fix the JSON, re-evaluate. Do not proceed on an invalid structure.
- Keep one session dir (`--out results/07_hydroagent/cc_discover/<basin>_<run>`)
  so `history.jsonl` accumulates the full trace.
- Honesty: structures YOU find interactively are "Claude-assisted discovery", not
  automated reproducible discovery — never claim the latter in any write-up.
