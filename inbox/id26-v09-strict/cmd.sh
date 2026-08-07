#!/bin/bash
# id26-v09-strict seq=3 : stage the v09 code + legacy checkpoints under ~/v09_strict.
# Touches ONLY ~/v09_strict and reads ~/hpc_mailbox/payload/id26.
# Does NOT touch ~/neuralhydrology, ~/adv531, ~/nature_1st_a02.
# No sbatch, no training.
export LC_ALL=C
ROOT="$HOME/v09_strict"
REPO="$ROOT/neuralhydrology"
BRANCH="codex/historical-band-experts-pilot"
WANT_COMMIT="f94183209bf44ed6e672e1c23f98020905804e6d"
TARBALL="$HOME/hpc_mailbox/payload/id26/legacy_18_lstm_fair_531.tar.gz"

echo "=== A GIT CAPABILITY (v09 code needs 'rev-parse --path-format=absolute --git-common-dir') ==="
echo "system git : $(git --version 2>&1)  at $(command -v git)"
git rev-parse --path-format=absolute --git-common-dir >/dev/null 2>&1 \
  && echo "system git supports --path-format : YES" || echo "system git supports --path-format : NO"
CONDA_GIT="$HOME/miniconda3/envs/nh_final/bin/git"
if [ -x "$CONDA_GIT" ]; then echo "conda git  : $($CONDA_GIT --version)"; else echo "conda git  : none"; fi
echo "-- module system --"
(module avail 2>&1 | grep -i "git" | head -5) 2>/dev/null || echo "(no module command)"

echo "=== B PAYLOAD PRESENT? ==="
if [ -f "$TARBALL" ]; then
  echo "ok $(stat -c%s "$TARBALL") bytes"
  echo "sha256=$(sha256sum "$TARBALL" | cut -d' ' -f1)"
  echo "expect=d5980dba3068a3715433c0217a02e476461db8b9afa0be8a9ce92ef76c6859ae"
else
  echo "MISSING $TARBALL"; exit 1
fi

echo "=== C CLONE CODE (shallow, single branch) ==="
mkdir -p "$ROOT"
if [ -d "$REPO/.git" ]; then
  echo "repo exists, fetching"
  cd "$REPO" || exit 1
  git fetch -q origin "+${BRANCH}:refs/remotes/origin/${BRANCH}" 2>&1 | tail -3
  git checkout -q "refs/remotes/origin/${BRANCH}" 2>&1 | tail -3
else
  git clone -q --depth 1 --branch "$BRANCH" --single-branch \
    git@github.com:yiqun-sun-rookie/neuralhydrology.git "$REPO" 2>&1 | tail -5
fi
cd "$REPO" 2>/dev/null || { echo "CLONE FAILED"; exit 1; }
GOT=$(git rev-parse HEAD 2>&1)
echo "HEAD     = $GOT"
echo "expected = $WANT_COMMIT"
[ "$GOT" = "$WANT_COMMIT" ] && echo "COMMIT MATCH: YES" || echo "COMMIT MATCH: NO"
echo "clone size: $(du -sh "$REPO" 2>/dev/null | cut -f1)"

echo "=== D EXTRACT LEGACY CHECKPOINTS ==="
tar xzf "$TARBALL" -C "$REPO" && echo "extracted"
echo "checkpoints: $(find "$REPO/results/18_lstm_fair_531" -name 'model_epoch030.pt' 2>/dev/null | wc -l) (want 8)"
echo "configs    : $(find "$REPO/results/18_lstm_fair_531" -name 'config.yml' 2>/dev/null | wc -l) (want 8)"

echo "=== E VERIFY CHECKPOINT HASHES AGAINST THE FROZEN PROTOCOL ==="
"$HOME/miniconda3/envs/nh_final/bin/python" - <<'PY' 2>&1 | tail -20
import hashlib, json, pathlib
repo = pathlib.Path.home() / "v09_strict" / "neuralhydrology"
proto = json.loads((repo / "src/26_historical_band_experts/configs/formal_v09_protocol.json").read_text(encoding="utf-8"))
bad = 0
for run in proto["legacy_reference"]["runs"]:
    d = repo / "results/18_lstm_fair_531" / run["run_id"]
    for name, key in (("config.yml", "config_sha256"), ("model_epoch030.pt", "checkpoint_epoch030_sha256")):
        p = d / name
        if not p.is_file():
            print(f"MISSING seed={run['seed']} {name}"); bad += 1; continue
        got = hashlib.sha256(p.read_bytes()).hexdigest()
        if got != run[key]:
            print(f"HASH DRIFT seed={run['seed']} {name}"); bad += 1
print(f"legacy checkpoint hash mismatches: {bad} (want 0)")
PY

echo "=== F WORKTREE MUST BE CLEAN (v09 gates require it) ==="
cd "$REPO" || exit 1
echo "dirty_files=$(git status --porcelain --untracked-files=all 2>/dev/null | wc -l)  (want 0)"

echo "=== G UPLOAD TARGET FOR THE 179 MB SEALED INPUT ==="
mkdir -p "$REPO/results/26_historical_band_experts"
echo "destination: $REPO/results/26_historical_band_experts/formal_v09"
ls -la "$REPO/results/26_historical_band_experts" 2>&1 | head -5
df -h /data1 2>&1 | tail -1

echo "=== END ==="
