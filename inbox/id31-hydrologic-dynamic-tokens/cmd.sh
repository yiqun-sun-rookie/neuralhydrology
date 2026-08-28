#!/usr/bin/env bash
set -eo pipefail

SOURCE=/data1/home/sunyiq/id30_modern_transformer_moe_20260827/repo
TARGET=/data1/home/sunyiq/id31_hydrologic_dynamic_tokens_20260828
STAGE=/data1/home/sunyiq/.id31_hydrologic_dynamic_tokens_20260828.staging_seq2
PAYLOAD="$HOME/hpc_mailbox/payload/id31-hydrologic-dynamic-tokens/id31_hydrologic_dynamic_tokens_code_20260828_v01.tar.gz"
EXPECTED_PAYLOAD_SHA256=0f1f158e21f3726008647d4f1a98561aca499380908f46538339d734822f2092
EXPECTED_SOURCE_REVISION=eef5ecf460775b679eabda36ca4df090c14d4e36

test -d "$SOURCE/.git"
test -f "$PAYLOAD"
test ! -e "$TARGET"
test -d "$STAGE/repo/.git"
test ! -e "$STAGE/repo/src/hydrologic_dynamic_tokens"
test ! -e "$STAGE/repo/data/camels_us_track0_development_forcing_v01"
test ! -e "$STAGE/repo/data/camels_us_track0_supervision_v01"

actual_payload_sha256=$(sha256sum "$PAYLOAD" | awk '{print $1}')
test "$actual_payload_sha256" = "$EXPECTED_PAYLOAD_SHA256"

cd "$STAGE/repo"
test "$(git rev-parse HEAD)" = "$EXPECTED_SOURCE_REVISION"
test "$(sha256sum neuralhydrology/modelzoo/__init__.py | awk '{print $1}')" = \
  49fd889aa309948270c66ebedc0578bff8502f37eee1ccf9354227871c4bd30d
test "$(sha256sum neuralhydrology/training/__init__.py | awk '{print $1}')" = \
  f41ec3daf713ed9b4021de6d2b0e25460bdf9996f4be38532ecf28dd244ecc15
test "$(sha256sum neuralhydrology/training/regularization.py | awk '{print $1}')" = \
  91414cc017b2903322de8069ca0879b86b1deefe73756c22058abdbc633d682c
test "$(sha256sum neuralhydrology/utils/config.py | awk '{print $1}')" = \
  8732ceb341ce81362aebfe0855f7ab6b677d5657badffc2e1e4f89f1c0f550bc

cp "$SOURCE/src/modern_transformer_moe/registry/track0_development_forcing_manifest_v01.json" \
   src/modern_transformer_moe/registry/
cp "$SOURCE/src/modern_transformer_moe/registry/track0_supervision_manifest_v01.json" \
   src/modern_transformer_moe/registry/

mkdir -p data
ln -s "$SOURCE/data/camels_us_track0_development_forcing_v01" \
      data/camels_us_track0_development_forcing_v01
ln -s "$SOURCE/data/camels_us_track0_supervision_v01" \
      data/camels_us_track0_supervision_v01

tar -xzf "$PAYLOAD"
mkdir -p logs/31_hydrologic_dynamic_tokens
mkdir -p results/31_hydrologic_dynamic_tokens/_reports
mkdir -p results/31_hydrologic_dynamic_tokens/_gpu_resource_probes

python - <<'PY'
import json
from pathlib import Path

pairs = (
    (
        Path("data/camels_us_track0_development_forcing_v01"),
        Path("src/modern_transformer_moe/registry/track0_development_forcing_manifest_v01.json"),
    ),
    (
        Path("data/camels_us_track0_supervision_v01"),
        Path("src/modern_transformer_moe/registry/track0_supervision_manifest_v01.json"),
    ),
)
for configured_path, manifest_path in pairs:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    actual = configured_path.resolve()
    expected = Path(manifest["output_dir"]).resolve()
    if actual != expected:
        raise ValueError(f"Safe-data link mismatch: {actual} != {expected}")
    print("SAFE_DATA_LINK", configured_path, "->", actual)
PY

python -m src.hydrologic_dynamic_tokens.scripts.audit_configs
python - <<'PY'
import json
from src.hydrologic_dynamic_tokens.scripts.run_development import capture_source_integrity

print(json.dumps(capture_source_integrity("DL01"), indent=2, sort_keys=True))
PY
bash -n src/hydrologic_dynamic_tokens/hpc/submit_gpu_resource_probe.slurm
bash -n src/hydrologic_dynamic_tokens/hpc/submit_development_experiment.slurm

cd /data1/home/sunyiq
mv "$STAGE" "$TARGET"
test -d "$TARGET/repo/.git"
test -d "$TARGET/repo/logs/31_hydrologic_dynamic_tokens"
echo "ID31_DEPLOYMENT_PASS"
