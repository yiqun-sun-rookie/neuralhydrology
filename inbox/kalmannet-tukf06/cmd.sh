#!/usr/bin/env bash
set -eo pipefail

TARGET=/data1/home/sunyiq/kalmannet_tukf06_20260809/retry2
OUTPUT="$TARGET/results/tukf06_full_diagonal_search_head_to_head_v1"
MAILBOX=/data1/home/sunyiq/hpc_mailbox
RETRIEVAL="$TARGET/retrieval"
DEST="$MAILBOX/outbox/kalmannet-tukf06/artifacts"
NAME=TUKF06_FULL_DIAGONAL_SEARCH_HEAD_TO_HEAD_V1_jobs_202136_202156_202157.tar.gz
ARCHIVE="$RETRIEVAL/$NAME"
MANIFEST="$RETRIEVAL/package_manifest.json"
CHECKSUMS="$RETRIEVAL/package_checksums.json"
SELECTION_MANIFEST_SHA=63160e786c2b6b07bbb144766deda8bdc29c86d889dbeb8a0f81d468623bc8c3
SELECTION_SEAL_SHA=9151f439e110a679802739eadd7a21857ab396e824ce3c4ea01052b6c611e35a
EVALUATION_SUMMARY_SHA=f053e8f9af10ec82e4005ed113e7d987bf4a9f09399383b4411e3d55a9720a9d
EVALUATION_MANIFEST_SHA=50fbdc6c44efa9e055f1ebd8772c992bb98dc9ca77a854d676954cd39f609965

for job in 202136 202143 202156 202157; do
  state=$(sacct -j "$job" -X -n -o State | awk 'NF {print $1; exit}')
  exit_code=$(sacct -j "$job" -X -n -o ExitCode | awk 'NF {print $1; exit}')
  if [[ "$state" != "COMPLETED" || "$exit_code" != "0:0" ]]; then
    echo "prerequisite job gate failed: job=$job state=$state exit_code=$exit_code" >&2
    exit 131
  fi
done
test ! -e "$OUTPUT/evaluation_failed.json"
test ! -s "$TARGET/logs/evaluation-202156.err"
test ! -s "$TARGET/audit/selection-audit-202143.err"
test ! -s "$TARGET/audit/evaluation-audit-202157.err"
grep -F 'TUKF06_SELECTION_READ_ONLY_AUDIT_PASS' "$TARGET/audit/selection-audit-202143.out"
grep -F 'TUKF06_EVALUATION_READ_ONLY_AUDIT_PASS' "$TARGET/audit/evaluation-audit-202157.out"
test "$(sha256sum "$OUTPUT/selection_manifest.sha256.json" | awk '{print $1}')" = "$SELECTION_MANIFEST_SHA"
test "$(sha256sum "$OUTPUT/selection.sealed.json" | awk '{print $1}')" = "$SELECTION_SEAL_SHA"
test "$(sha256sum "$OUTPUT/evaluation_summary.json" | awk '{print $1}')" = "$EVALUATION_SUMMARY_SHA"
test "$(sha256sum "$OUTPUT/evaluation_manifest.sha256.json" | awk '{print $1}')" = "$EVALUATION_MANIFEST_SHA"

mkdir -p "$RETRIEVAL" "$DEST"
for path in "$ARCHIVE" "$ARCHIVE.pending" "$MANIFEST" "$CHECKSUMS" \
  "$DEST/$NAME" "$DEST/$NAME.pending" "$DEST/package_manifest.json" \
  "$DEST/package_manifest.json.pending" "$DEST/package_checksums.json" \
  "$DEST/package_checksums.json.pending"; do
  if [[ -e "$path" ]]; then
    echo "refusing to overwrite retrieval artifact: $path" >&2
    exit 132
  fi
done

python - "$TARGET" "$MANIFEST" <<'PY'
import hashlib
import json
import os
import pathlib
import sys

root = pathlib.Path(sys.argv[1]).resolve()
destination = pathlib.Path(sys.argv[2]).resolve()
included_roots = ('source', 'results', 'logs', 'audit', 'smoke')

def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()

files = {}
total_bytes = 0
for top in included_roots:
    base = root / top
    assert base.is_dir(), base
    for path in sorted(base.rglob('*')):
        relative = path.relative_to(root)
        if '__pycache__' in relative.parts or path.suffix == '.pyc':
            continue
        if path.is_symlink():
            raise RuntimeError(f'symlink is forbidden in package: {relative}')
        if path.is_file():
            size = path.stat().st_size
            files[relative.as_posix()] = {'sha256': sha(path), 'bytes': size}
            total_bytes += size

payload = {
    'experiment_id': 'TUKF06_FULL_DIAGONAL_SEARCH_HEAD_TO_HEAD_V1',
    'remote_root': str(root),
    'included_roots': list(included_roots),
    'excluded_runtime_cache_patterns': ['**/__pycache__/**', '**/*.pyc'],
    'jobs': {
        'selection': '202136',
        'selection_audit': '202143',
        'evaluation': '202156',
        'evaluation_audit': '202157',
    },
    'selection_manifest_sha256': '63160e786c2b6b07bbb144766deda8bdc29c86d889dbeb8a0f81d468623bc8c3',
    'selection_seal_sha256': '9151f439e110a679802739eadd7a21857ab396e824ce3c4ea01052b6c611e35a',
    'evaluation_summary_sha256': 'f053e8f9af10ec82e4005ed113e7d987bf4a9f09399383b4411e3d55a9720a9d',
    'evaluation_manifest_sha256': '50fbdc6c44efa9e055f1ebd8772c992bb98dc9ca77a854d676954cd39f609965',
    'file_count': len(files),
    'total_uncompressed_file_bytes': total_bytes,
    'files': files,
}
temporary = destination.with_suffix(destination.suffix + '.pending')
with temporary.open('x', encoding='utf-8', newline='\n') as handle:
    json.dump(payload, handle, indent=2, sort_keys=True, allow_nan=False)
    handle.write('\n')
    handle.flush()
    os.fsync(handle.fileno())
os.replace(temporary, destination)
print(f'PACKAGE_MANIFEST_WRITTEN files={len(files)} bytes={total_bytes}')
PY

tar --exclude='*/__pycache__' --exclude='*.pyc' -C "$TARGET" -czf "$ARCHIVE.pending" \
  source results logs audit smoke retrieval/package_manifest.json
archive_bytes=$(wc -c < "$ARCHIVE.pending")
if [[ "$archive_bytes" -ge 94371840 ]]; then
  echo "retrieval archive is at least 90 MiB: $archive_bytes" >&2
  exit 133
fi
mv "$ARCHIVE.pending" "$ARCHIVE"

python - "$TARGET" "$ARCHIVE" "$MANIFEST" "$CHECKSUMS" <<'PY'
import hashlib
import json
import os
import pathlib
import sys
import tarfile

root = pathlib.Path(sys.argv[1]).resolve()
archive = pathlib.Path(sys.argv[2]).resolve()
manifest_path = pathlib.Path(sys.argv[3]).resolve()
checksums_path = pathlib.Path(sys.argv[4]).resolve()

def sha_bytes(data):
    return hashlib.sha256(data).hexdigest()

def sha_file(path):
    digest = hashlib.sha256()
    with path.open('rb') as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()

manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
expected_files = set(manifest['files']) | {'retrieval/package_manifest.json'}
with tarfile.open(archive, 'r:gz') as handle:
    file_members = {}
    for member in handle.getmembers():
        name = pathlib.PurePosixPath(member.name).as_posix().lstrip('./')
        if name.startswith('/') or '..' in pathlib.PurePosixPath(name).parts:
            raise RuntimeError(f'unsafe archive member: {member.name}')
        if member.isfile():
            file_members[name] = member
    assert set(file_members) == expected_files, (
        sorted(expected_files - set(file_members)), sorted(set(file_members) - expected_files))
    for relative, expected in manifest['files'].items():
        extracted = handle.extractfile(file_members[relative])
        assert extracted is not None
        data = extracted.read()
        assert len(data) == expected['bytes'], relative
        assert sha_bytes(data) == expected['sha256'], relative
    embedded = handle.extractfile(file_members['retrieval/package_manifest.json']).read()
    assert sha_bytes(embedded) == sha_file(manifest_path)

payload = {
    'archive_name': archive.name,
    'archive_bytes': archive.stat().st_size,
    'archive_sha256': sha_file(archive),
    'package_manifest_sha256': sha_file(manifest_path),
    'verified_file_count': len(manifest['files']),
    'status': 'PACKAGE_VERIFIED',
}
temporary = checksums_path.with_suffix(checksums_path.suffix + '.pending')
with temporary.open('x', encoding='utf-8', newline='\n') as out:
    json.dump(payload, out, indent=2, sort_keys=True, allow_nan=False)
    out.write('\n')
    out.flush()
    os.fsync(out.fileno())
os.replace(temporary, checksums_path)
print(json.dumps(payload, sort_keys=True))
PY

cp "$ARCHIVE" "$DEST/$NAME.pending"
cp "$MANIFEST" "$DEST/package_manifest.json.pending"
cp "$CHECKSUMS" "$DEST/package_checksums.json.pending"
test "$(sha256sum "$ARCHIVE" | awk '{print $1}')" = "$(sha256sum "$DEST/$NAME.pending" | awk '{print $1}')"
test "$(sha256sum "$MANIFEST" | awk '{print $1}')" = "$(sha256sum "$DEST/package_manifest.json.pending" | awk '{print $1}')"
test "$(sha256sum "$CHECKSUMS" | awk '{print $1}')" = "$(sha256sum "$DEST/package_checksums.json.pending" | awk '{print $1}')"
mv "$DEST/$NAME.pending" "$DEST/$NAME"
mv "$DEST/package_manifest.json.pending" "$DEST/package_manifest.json"
mv "$DEST/package_checksums.json.pending" "$DEST/package_checksums.json"

cd "$MAILBOX"
git add "outbox/kalmannet-tukf06/artifacts/$NAME" \
  outbox/kalmannet-tukf06/artifacts/package_manifest.json \
  outbox/kalmannet-tukf06/artifacts/package_checksums.json
staged=$(git diff --cached --name-only)
expected=$(printf '%s\n' \
  "outbox/kalmannet-tukf06/artifacts/$NAME" \
  outbox/kalmannet-tukf06/artifacts/package_checksums.json \
  outbox/kalmannet-tukf06/artifacts/package_manifest.json)
if [[ "$staged" != "$expected" ]]; then
  echo "unexpected staged retrieval paths" >&2
  printf 'staged:\n%s\nexpected:\n%s\n' "$staged" "$expected" >&2
  exit 134
fi
git -c core.autocrlf=false commit -q -m 'hpc-mailbox: return TUKF06 verified evidence'
git fetch -q origin '+refs/heads/hpc-mailbox:refs/remotes/origin/hpc-mailbox'
git rebase -q refs/remotes/origin/hpc-mailbox
git push -q origin HEAD:hpc-mailbox
echo "TUKF06_VERIFIED_EVIDENCE_PUSHED commit=$(git rev-parse HEAD)"
cat "$CHECKSUMS"
