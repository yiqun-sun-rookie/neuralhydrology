#!/usr/bin/env bash
set -eo pipefail

TARGET=/data1/home/sunyiq/kalmannet_tukf06_20260809/retry2
RETRIEVAL="$TARGET/retrieval"
MAILBOX=/data1/home/sunyiq/hpc_mailbox
DEST="$MAILBOX/outbox/kalmannet-tukf06/artifacts"
NAME=TUKF06_FULL_DIAGONAL_SEARCH_HEAD_TO_HEAD_V1_jobs_202136_202156_202157.tar.gz
ARCHIVE="$RETRIEVAL/$NAME"
MANIFEST="$RETRIEVAL/package_manifest.json"
CHECKSUMS="$RETRIEVAL/package_checksums.json"
EXPECTED_ARCHIVE_SHA=28e67a9b9b2407c1be4c006c76b8ff7da090342a4921465dd2c935c4cb9940b7
EXPECTED_ARCHIVE_BYTES=12466592
EXPECTED_MANIFEST_SHA=56ad1d4e17c016ed25c6f5c225854484e0adc5de8401a08b9c55b581d94f67b7

test -f "$ARCHIVE" -a -f "$MANIFEST" -a -f "$CHECKSUMS"
test "$(wc -c < "$ARCHIVE")" = "$EXPECTED_ARCHIVE_BYTES"
test "$(sha256sum "$ARCHIVE" | awk '{print $1}')" = "$EXPECTED_ARCHIVE_SHA"
test "$(sha256sum "$MANIFEST" | awk '{print $1}')" = "$EXPECTED_MANIFEST_SHA"
python - "$CHECKSUMS" "$EXPECTED_ARCHIVE_SHA" "$EXPECTED_ARCHIVE_BYTES" "$EXPECTED_MANIFEST_SHA" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
assert payload == {
    'archive_name': 'TUKF06_FULL_DIAGONAL_SEARCH_HEAD_TO_HEAD_V1_jobs_202136_202156_202157.tar.gz',
    'archive_bytes': int(sys.argv[3]),
    'archive_sha256': sys.argv[2],
    'package_manifest_sha256': sys.argv[4],
    'verified_file_count': 169,
    'status': 'PACKAGE_VERIFIED',
}
print('SOURCE_RETRIEVAL_PACKAGE_REVERIFIED')
PY

mkdir -p "$DEST"
ATTR="$DEST/.gitattributes"
if [[ -e "$ATTR" ]]; then
  test "$(cat "$ATTR")" = '*.tar.gz -text'
else
  printf '%s\n' '*.tar.gz -text' > "$ATTR"
fi

copy_if_absent_or_verify() {
  source_path=$1
  destination_path=$2
  if [[ -e "$destination_path" ]]; then
    test -f "$destination_path"
    test "$(sha256sum "$source_path" | awk '{print $1}')" = "$(sha256sum "$destination_path" | awk '{print $1}')"
  else
    cp "$source_path" "$destination_path.pending"
    test "$(sha256sum "$source_path" | awk '{print $1}')" = "$(sha256sum "$destination_path.pending" | awk '{print $1}')"
    mv "$destination_path.pending" "$destination_path"
  fi
}

copy_if_absent_or_verify "$ARCHIVE" "$DEST/$NAME"
copy_if_absent_or_verify "$MANIFEST" "$DEST/package_manifest.json"
copy_if_absent_or_verify "$CHECKSUMS" "$DEST/package_checksums.json"

cd "$MAILBOX"
attribute=$(git check-attr text -- "outbox/kalmannet-tukf06/artifacts/$NAME" | awk -F': ' '{print $3}')
if [[ "$attribute" != "unset" ]]; then
  echo "archive text attribute was not disabled: $attribute" >&2
  exit 141
fi
git add \
  outbox/kalmannet-tukf06/artifacts/.gitattributes \
  "outbox/kalmannet-tukf06/artifacts/$NAME" \
  outbox/kalmannet-tukf06/artifacts/package_checksums.json \
  outbox/kalmannet-tukf06/artifacts/package_manifest.json

archive_blob=$(git rev-parse ":outbox/kalmannet-tukf06/artifacts/$NAME")
test "$(git cat-file -s "$archive_blob")" = "$EXPECTED_ARCHIVE_BYTES"
test "$(git cat-file blob "$archive_blob" | sha256sum | awk '{print $1}')" = "$EXPECTED_ARCHIVE_SHA"
staged=$(git diff --cached --name-only)
expected=$(printf '%s\n' \
  outbox/kalmannet-tukf06/artifacts/.gitattributes \
  "outbox/kalmannet-tukf06/artifacts/$NAME" \
  outbox/kalmannet-tukf06/artifacts/package_checksums.json \
  outbox/kalmannet-tukf06/artifacts/package_manifest.json)
if [[ "$staged" != "$expected" ]]; then
  echo "unexpected staged retrieval paths" >&2
  printf 'staged:\n%s\nexpected:\n%s\n' "$staged" "$expected" >&2
  exit 142
fi
unstaged=$(git diff --name-only)
if [[ -n "$unstaged" ]]; then
  echo "unstaged mailbox changes prevent safe retrieval push" >&2
  printf '%s\n' "$unstaged" >&2
  exit 143
fi

git -c core.autocrlf=false commit -q -m 'hpc-mailbox: return TUKF06 binary evidence'
git fetch -q origin '+refs/heads/hpc-mailbox:refs/remotes/origin/hpc-mailbox'
git rebase -q refs/remotes/origin/hpc-mailbox
git push -q origin HEAD:hpc-mailbox
echo "TUKF06_BINARY_EVIDENCE_PUSHED commit=$(git rev-parse HEAD)"
echo "archive_sha256=$EXPECTED_ARCHIVE_SHA"
echo "archive_bytes=$EXPECTED_ARCHIVE_BYTES"
echo "package_manifest_sha256=$EXPECTED_MANIFEST_SHA"
