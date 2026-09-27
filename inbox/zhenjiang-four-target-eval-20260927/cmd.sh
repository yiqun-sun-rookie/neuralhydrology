#!/bin/bash
set -euo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B - <<'RETRIEVE_FROZEN_FOUR_TARGET'
from pathlib import Path
import hashlib,json,base64
requests=json.loads('[{"bytes":20232,"local":"weights/17/common_process.pt","path":"/data1/home/sunyiq/zhenjiang_four_target_retrain_20260924_001/run/seed_17/common_process/epoch_26.pt","sha256":"f1b85033666c3db911fbf8ff7a876dcf8d4b08a2396ea66e4968c1f496734595"},{"bytes":1688,"local":"weights/17/differentiable_filter.pt","path":"/data1/home/sunyiq/zhenjiang_four_target_retrain_20260924_001/run/seed_17/differentiable_filter/epoch_97.pt","sha256":"88cd96ef1d9deb02597febcb701999f44db15a5d06cd126806f8c518b50dc583"},{"bytes":66568,"local":"weights/17/rolling_encoder.pt","path":"/data1/home/sunyiq/zhenjiang_four_target_retrain_20260924_001/run/seed_17/rolling_encoder/epoch_95.pt","sha256":"a49b6addc67eb5222dc7224fa935d7def399a1b9d247a189440a2fde8678dee3"},{"bytes":20232,"local":"weights/29/common_process.pt","path":"/data1/home/sunyiq/zhenjiang_four_target_retrain_20260924_001/run/seed_29/common_process/epoch_29.pt","sha256":"5d62fb6018791d9c05d8340cab4aeebdc8033e1c203e15670e47127026946d4f"},{"bytes":1688,"local":"weights/29/differentiable_filter.pt","path":"/data1/home/sunyiq/zhenjiang_four_target_retrain_20260924_001/run/seed_29/differentiable_filter/epoch_97.pt","sha256":"0e1295f66a6353aa48e847267d8f2920029bdca3a0fbc3d9adc7022aaa93a2f9"},{"bytes":66568,"local":"weights/29/rolling_encoder.pt","path":"/data1/home/sunyiq/zhenjiang_four_target_retrain_20260924_001/run/seed_29/rolling_encoder/epoch_93.pt","sha256":"aa23ce9b83991ef78388492dde00b4e1e49bc2f37bc368cf0fbd8fac257adda0"},{"bytes":20232,"local":"weights/43/common_process.pt","path":"/data1/home/sunyiq/zhenjiang_four_target_retrain_20260924_001/run/seed_43/common_process/epoch_26.pt","sha256":"5e083b6158a1a332da341f0ea59550abd446f6e9de6c3fe7341d7f5284e62769"},{"bytes":1688,"local":"weights/43/differentiable_filter.pt","path":"/data1/home/sunyiq/zhenjiang_four_target_retrain_20260924_001/run/seed_43/differentiable_filter/epoch_100.pt","sha256":"395b5af5380d52e535fefd85437e3e1d657cd0773f686c23e19e9e1a56cad50d"},{"bytes":66568,"local":"weights/43/rolling_encoder.pt","path":"/data1/home/sunyiq/zhenjiang_four_target_retrain_20260924_001/run/seed_43/rolling_encoder/epoch_98.pt","sha256":"c92ad1ab0a697c8a7407bc52b05fb946a842f0438b95db39f89737a5216ef8e6"},{"bytes":10525,"local":"preparation.json","path":"/data1/home/sunyiq/zhenjiang_shared_base_no_training_time_cap_20260917_001/preflight/preparation.json","sha256":"5a4be84658540e57a000a50a94179630f60bd88e5af060dc94aa25fe8cc5d8e9"}]')
assert len(requests)==10 and sum(s['bytes'] for s in requests)==275989
out=[]
for s in requests:
    p=Path(s['path'])
    assert p.is_file() and not p.is_symlink() and p.stat().st_size==s['bytes']
    raw=p.read_bytes()
    assert hashlib.sha256(raw).hexdigest()==s['sha256']
    out.append(dict(s,base64=base64.b64encode(raw).decode('ascii')))
print(json.dumps({'status':'verified_read_only_retrieval','files':out},sort_keys=True))

RETRIEVE_FROZEN_FOUR_TARGET
