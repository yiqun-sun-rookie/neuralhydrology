#!/usr/bin/env bash
set -euo pipefail

REMOTE_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901"
EXECUTION_ID="DAILY_CAMELS_KNET_PER_BASIN_PILOT_08070200_A800_TRAIN1_SEQ18"
RUN_DIRECTORY="${REMOTE_ROOT}/runs/${EXECUTION_ID}"
DEPLOY="${REMOTE_ROOT}/deployments/DAILY_CAMELS_KNET_PER_BASIN_BUNDLE_DEPLOY3_SEQ12/source"
EXPECTED_057_SHA256="e4d53ec2e51c74378a4ec87b5bd3d46f271966170cf1ff351c4f9c19fd4172c8"

echo '=== READ-ONLY TASK 0: CORRECTION-CAP REPLAY FALSIFICATION (08070200) ==='
date --iso-8601=seconds
hostname
echo 'channel=kalmannet-daily-perbasin sequence=30 purpose=read-only-cap-replay-no-optimizer'
echo 'signals_sent=0 submissions_created=0 files_modified=0 optimizer_steps=0 formal_evaluation_access=0 device=cpu'

if [[ ! -d "${DEPLOY}" ]]; then echo "DEPLOYMENT SOURCE MISSING: ${DEPLOY}" >&2; exit 201; fi
if [[ ! -d "${RUN_DIRECTORY}/checkpoints" ]]; then echo 'RUN CHECKPOINT DIRECTORY MISSING' >&2; exit 202; fi

CK49="${RUN_DIRECTORY}/checkpoints/epoch_049.pt"
CK57="${RUN_DIRECTORY}/checkpoints/epoch_057.pt"
for f in "${CK49}" "${CK57}"; do
  if [[ ! -f "${f}" ]]; then echo "MISSING ${f}" >&2; exit 203; fi
  echo "$(sha256sum "${f}" | awk '{print $1}')  $(stat -c '%s' "${f}")  $(basename "${f}")"
done
if [[ "$(sha256sum "${CK57}" | awk '{print $1}')" != "${EXPECTED_057_SHA256}" ]]; then
  echo 'epoch_057 checkpoint hash changed' >&2; exit 204
fi
echo 'epoch_057_identity=MATCHES_REGISTERED_AUDIT'

export PYTHONPATH="${DEPLOY}:${DEPLOY}/src"
export OMP_NUM_THREADS=4
export MKL_NUM_THREADS=4
cd "${DEPLOY}"

python - "${RUN_DIRECTORY}" "${DEPLOY}" <<'PY'
import sys, math, importlib.util
from pathlib import Path

run_dir = Path(sys.argv[1]); deploy = Path(sys.argv[2])
EPOCH_ZERO_OBJECTIVE = 0.8455348749210457
CAP = 3.0
SEED = 20260824
print("epoch_zero_checkpoint_objective_728 = %.16g" % EPOCH_ZERO_OBJECTIVE, flush=True)

import torch
torch.set_num_threads(4)
from global_hydrology.experiments.daily_camels_knet_per_basin_contract import (
    get_pilot_basin_specification)
from global_hydrology.experiments.daily_camels_knet_per_basin_runner import (
    build_exact_dimension_kalman_net, load_per_basin_development_runtime)
from global_hydrology.experiments.daily_camels_ukf_knet_parity_contract import (
    AccessLedger, CAUSAL_SHARED_SPINUP_MODE)
from global_hydrology.experiments.daily_camels_ukf_knet_parity_runner import (
    evaluate_knet, select_window, segment_multilead_mse, training_open_loop_states)

ledger = AccessLedger()
spec = get_pilot_basin_specification("08070200")
runtime = load_per_basin_development_runtime(
    spec, ledger=ledger, initialization_mode=CAUSAL_SHARED_SPINUP_MODE,
    device=torch.device("cpu"))
recovery = select_window(runtime, "recovery")
print("runtime_ready state_dimension=%d" % int(runtime.context.dimension), flush=True)

def build():
    return build_exact_dimension_kalman_net(
        runtime, zero_gain=False, seed=SEED, hidden=24,
        input_multiplier=10, output_multiplier=10,
        feature_scale_floor=0.1, normalized_feature_guard=10.0)

printed = {}

def find_model_state(obj, depth=0):
    if depth > 4:
        return None
    if isinstance(obj, dict):
        if "model_state" in obj:
            return obj["model_state"]
        if any(isinstance(k, str) and k.startswith("FC2.") for k in obj):
            return obj
        for v in obj.values():
            r = find_model_state(v, depth + 1)
            if r is not None:
                return r
    if hasattr(obj, "model_state"):
        return getattr(obj, "model_state")
    return None

def load_params(path):
    raw = torch.load(str(path), map_location="cpu", weights_only=False)
    if str(path) not in printed:
        printed[str(path)] = True
        if isinstance(raw, dict):
            keys = sorted(k for k in raw if isinstance(k, str))
            print("  %s top_level_keys=%s" % (Path(path).name, keys[:14]), flush=True)
        else:
            print("  %s top_level_type=%s" % (Path(path).name, type(raw).__name__), flush=True)
    st = find_model_state(raw)
    if st is None:
        raise RuntimeError("model_state not found in %s" % path)
    return st

def run_case(ckpt_path, cap_value, label):
    net = build()
    net.load_state_dict(load_params(ckpt_path), strict=True)
    net.eval()
    if cap_value is None:
        cap_desc = "inf-v1-control"
    else:
        net.correction_cap_by_state_scale_units.fill_(float(cap_value))
        cap_desc = "%.1f" % cap_value
    counters = {"sat": 0, "tot": 0, "steps": 0}
    original = net.analysis_step
    def wrapped(observation, controls):
        out = original(observation, controls)
        c = (net.last_correction / net.state_feature_scale).detach()
        counters["sat"] += int((c.abs() >= CAP * (1 - 1e-9)).sum())
        counters["tot"] += int(c.numel())
        counters["steps"] += 1
        return out
    net.analysis_step = wrapped
    try:
        with torch.no_grad():
            result = evaluate_knet(net, runtime, recovery)
        obj = float(result.full_objective_without_warmup)
        finite = math.isfinite(obj)
        ratio = obj / EPOCH_ZERO_OBJECTIVE if finite else float("inf")
        verdict = "PASS" if (finite and ratio < 100.0) else "FAIL"
        frac = counters["sat"] / counters["tot"] if counters["tot"] else float("nan")
        print("%-30s cap=%-16s objective_728=%.6e finite=%s ratio=%.6e  %s"
              % (label, cap_desc, obj, finite, ratio, verdict), flush=True)
        print("      analysis_steps=%d saturated=%d of %d (%.4f percent)"
              % (counters["steps"], counters["sat"], counters["tot"], 100.0 * frac), flush=True)
        return verdict
    except Exception as exc:
        print("%-30s cap=%-16s RAISED %s: %s   FAIL"
              % (label, cap_desc, type(exc).__name__, str(exc)[:120]), flush=True)
        return "FAIL"

print("=== TASK 0 CRITERION: cap 3.0 on the 731-day validation rollout ===", flush=True)
v57 = run_case(run_dir / "checkpoints" / "epoch_057.pt", CAP, "epoch_057 capped")
v49 = run_case(run_dir / "checkpoints" / "epoch_049.pt", CAP, "epoch_049 capped")
print("TASK_0_VERDICT=%s  (pre-registered: both finite and ratio < 100)"
      % ("PASS" if (v57 == "PASS" and v49 == "PASS") else "FAIL"), flush=True)

print("=== CONTROLS: same parameters, no cap (must reproduce v1) ===", flush=True)
run_case(run_dir / "checkpoints" / "epoch_057.pt", None, "epoch_057 uncapped")
run_case(run_dir / "checkpoints" / "epoch_049.pt", None, "epoch_049 uncapped")
print("v1 recorded: epoch_057 = 2.255994510923417e+243 ; epoch_049 = 8.846818181048675e+131", flush=True)

print("=== DIAGNOSIS CLOSURE: epoch-58 no-update forward and backward, full gradient scan ===", flush=True)
try:
    script_path = deploy / "scripts" / "run_daily_camels_knet_per_basin_pilot.py"
    s = importlib.util.spec_from_file_location("pilot_run", str(script_path))
    m = importlib.util.module_from_spec(s)
    s.loader.exec_module(m)
    net = build()
    net.load_state_dict(load_params(run_dir / "checkpoints" / "epoch_057.pt"), strict=True)
    net.train()
    for p in net.parameters():
        p.grad = None
    ols = training_open_loop_states(runtime)
    def segment_builder(start):
        return segment_multilead_mse(net, runtime, start=int(start),
                                     segment_days=150, filter_warmup_days=45,
                                     open_loop_states=ols)
    diag = m.backward_equal_segment_objective(
        starts=m.FIXED_TRAINING_SEGMENT_STARTS, segment_builder=segment_builder,
        leads=m.LEADS, torch_module=torch)
    print("  epoch58_forward_objective=%.10g events=%s"
          % (float(diag["training_objective"]), diag["training_forecast_error_events"]), flush=True)
    rows = []
    for name, p in net.named_parameters():
        if p.grad is None:
            rows.append((name, "NO_GRAD", "", ""))
            continue
        g = p.grad.detach()
        nan = int(torch.isnan(g).sum())
        posinf = int(torch.isposinf(g).sum())
        neginf = int(torch.isneginf(g).sum())
        fin = torch.isfinite(g)
        mx = float(g[fin].abs().max()) if bool(fin.any()) else float("nan")
        rows.append((name, "FINITE" if (nan + posinf + neginf) == 0 else "NONFINITE",
                     "nan=%d posinf=%d neginf=%d" % (nan, posinf, neginf),
                     "max_finite_abs=%.6e" % mx))
    print("  registration-order scan; v1 stopped at the first NONFINITE below:", flush=True)
    for name, status, counts, mx in rows:
        print("    %-32s %-9s %-28s %s" % (name, status, counts, mx), flush=True)
    bad = [r[0] for r in rows if r[1] == "NONFINITE"]
    print("  nonfinite_parameter_count=%d names=%s" % (len(bad), bad), flush=True)
    print("  float32_max=3.4028235e+38", flush=True)
except Exception as exc:
    print("  GRADIENT SCAN UNAVAILABLE: %s: %s" % (type(exc).__name__, str(exc)[:200]), flush=True)

print("formal_evaluation_access_count=%d" % int(getattr(ledger, "access_count", 0)), flush=True)
PY

echo '=== QUERY COMPLETE: READ ONLY, NO OPTIMIZER STEP, NO SUBMISSION, NO SIGNAL, NO WRITE ==='
