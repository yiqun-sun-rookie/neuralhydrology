#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export CUDA_VISIBLE_DEVICES=""
export PYTHONDONTWRITEBYTECODE=1
export OMP_NUM_THREADS=2
python -B - <<'UNPACK'
import hashlib,io,pathlib,tarfile
inbox=pathlib.Path('inbox/zhenjiang-six-source-four-target-ukf')
sequence=int((inbox/'seq').read_text());assert sequence==673
raw=(inbox/f'payload_complete_comparison_20261006_{sequence}.tar.gz').read_bytes()
assert hashlib.sha256(raw).hexdigest()=='a839057de7f4b9c6a19adad8484fb3081b09eaa509ae5708b087eae60362262f'
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_fixed200_003_candidates_20261019_001')
assert not root.exists(),'preserve existing candidate root; reconcile instead of replay'
root.mkdir()
with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as archive:
 members=archive.getmembers()
 assert len({m.name for m in members})==len(members)
 for member in members:
  relative=pathlib.PurePosixPath(member.name)
  assert member.isfile() and not relative.is_absolute() and '..' not in relative.parts
  target=root/member.name;target.parent.mkdir(parents=True,exist_ok=True)
  with target.open('xb') as stream:stream.write(archive.extractfile(member).read())
UNPACK
python -B /data1/home/sunyiq/zhenjiang_fixed200_003_candidates_20261019_001/prepare_candidates_remote.py
