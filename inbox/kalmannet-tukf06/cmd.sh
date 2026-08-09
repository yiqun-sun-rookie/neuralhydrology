#!/usr/bin/env bash
set -eo pipefail

TARGET=/data1/home/sunyiq/kalmannet_tukf06_20260809/retry2
RETRIEVAL="$TARGET/retrieval"
SOURCE_MAILBOX=/data1/home/sunyiq/hpc_mailbox
CLONE="$RETRIEVAL/mailbox_push_clone_v3"
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
if [[ -e "$CLONE" ]]; then
  echo "refusing to reuse retrieval push clone: $CLONE" >&2
  exit 151
fi

origin_url=$(cd "$SOURCE_MAILBOX" && git config --get remote.origin.url)
test -n "$origin_url"
git clone -q -b hpc-mailbox --single-branch --no-checkout "$origin_url" "$CLONE"
cd "$CLONE"
git config core.autocrlf false
git config core.safecrlf false
git config core.sparseCheckout true
printf '%s\n' \
  '/inbox/kalmannet-tukf06/' \
  '/outbox/kalmannet-tukf06/' > .git/info/sparse-checkout
git checkout -q hpc-mailbox
DEST="$CLONE/outbox/kalmannet-tukf06/artifacts"
mkdir -p "$DEST"
for path in "$DEST/.gitattributes" "$DEST/$NAME" \
  "$DEST/package_manifest.json" "$DEST/package_checksums.json"; do
  if [[ -e "$path" ]]; then
    echo "fresh clone unexpectedly contains retrieval artifact: $path" >&2
    exit 152
  fi
done

printf '%s\n' '*.tar.gz -text' > "$DEST/.gitattributes"
cp "$ARCHIVE" "$DEST/$NAME"
cp "$MANIFEST" "$DEST/package_manifest.json"
cp "$CHECKSUMS" "$DEST/package_checksums.json"
test "$(sha256sum "$DEST/$NAME" | awk '{print $1}')" = "$EXPECTED_ARCHIVE_SHA"
test "$(wc -c < "$DEST/$NAME")" = "$EXPECTED_ARCHIVE_BYTES"

cd "$CLONE"
attribute=$(git check-attr text -- "outbox/kalmannet-tukf06/artifacts/$NAME" | awk -F': ' '{print $3}')
if [[ "$attribute" != "unset" ]]; then
  echo "archive text attribute was not disabled: $attribute" >&2
  exit 153
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
  echo "unexpected staged retrieval paths in isolated clone" >&2
  printf 'staged:\n%s\nexpected:\n%s\n' "$staged" "$expected" >&2
  exit 154
fi
test -z "$(git diff --name-only)"

git -c core.autocrlf=false commit -q -m 'hpc-mailbox: return TUKF06 binary evidence'
git fetch -q origin '+refs/heads/hpc-mailbox:refs/remotes/origin/hpc-mailbox'
git rebase -q refs/remotes/origin/hpc-mailbox
git push -q origin HEAD:hpc-mailbox
git fetch -q origin '+refs/heads/hpc-mailbox:refs/remotes/origin/hpc-mailbox'
remote_spec="refs/remotes/origin/hpc-mailbox:outbox/kalmannet-tukf06/artifacts/$NAME"
remote_blob=$(git rev-parse "$remote_spec")
test "$(git cat-file -s "$remote_blob")" = "$EXPECTED_ARCHIVE_BYTES"
test "$(git cat-file blob "$remote_blob" | sha256sum | awk '{print $1}')" = "$EXPECTED_ARCHIVE_SHA"
echo "TUKF06_ISOLATED_BINARY_EVIDENCE_PUSHED commit=$(git rev-parse HEAD)"
echo "archive_sha256=$EXPECTED_ARCHIVE_SHA"
echo "archive_bytes=$EXPECTED_ARCHIVE_BYTES"
echo "package_manifest_sha256=$EXPECTED_MANIFEST_SHA"
