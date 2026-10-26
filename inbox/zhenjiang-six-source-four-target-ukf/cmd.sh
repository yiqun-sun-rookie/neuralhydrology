#!/usr/bin/env bash
set -eo pipefail
python3 - <<'READ_IMMUTABLE_PRIORITY_CHUNK'
import base64,hashlib,json
from pathlib import Path
spool=Path('/data1/home/sunyiq/zhenjiang_priority_source_export_20261026_001')
report=json.loads((spool/'MANIFEST.json').read_bytes())
assert report['archive_sha256']=='67cc6fc89bdebdf03d27a7153abda29e4c443ffeba429214d4a17d2949fe0e59'
index=2
expected=report['chunks'][index]
assert (spool/'source.tar.gz').stat().st_size==report['archive_bytes']
with (spool/'source.tar.gz').open('rb') as f:
 f.seek(sum(v['bytes'] for v in report['chunks'][:index]));data=f.read(expected['bytes'])
assert hashlib.sha256(data).hexdigest()==expected['sha256']
print('BEGIN_003_PRIORITY_CHUNK_BASE64',flush=True)
print(base64.b64encode(data).decode(),flush=True)
print('END_003_PRIORITY_CHUNK_BASE64',flush=True)
print(json.dumps({'chunk_index':index,'chunk_sha256':expected['sha256'],'archive_sha256':report['archive_sha256']}),flush=True)
READ_IMMUTABLE_PRIORITY_CHUNK
