#!/usr/bin/env bash
set -eo pipefail

TARGET=/data1/home/sunyiq/kalmannet_tukf06_20260809/retry2
RETRIEVAL="$TARGET/retrieval"
SOURCE_MAILBOX=/data1/home/sunyiq/hpc_mailbox
CLONE="$RETRIEVAL/mailbox_push_clone_v4"
NAME=TUKF06_FULL_DIAGONAL_SEARCH_HEAD_TO_HEAD_V1_jobs_202136_202156_202157.tar.gz
ARCHIVE="$RETRIEVAL/$NAME"
MANIFEST="$RETRIEVAL/package_manifest.json"
CHECKSUMS="$RETRIEVAL/package_checksums.json"
EXPECTED_ARCHIVE_SHA=28e67a9b9b2407c1be4c006c76b8ff7da090342a4921465dd2c935c4cb9940b7
EXPECTED_ARCHIVE_BYTES=12466592
EXPECTED_MANIFEST_SHA=56ad1d4e17c016ed25c6f5c225854484e0adc5de8401a08b9c55b581d94f67b7
RELATIVE_ARCHIVE="outbox/kalmannet-tukf06/artifacts/$NAME"

test -f "$ARCHIVE" -a -f "$MANIFEST" -a -f "$CHECKSUMS"
test "$(wc -c < "$ARCHIVE")" = "$EXPECTED_ARCHIVE_BYTES"
test "$(sha256sum "$ARCHIVE" | awk '{print $1}')" = "$EXPECTED_ARCHIVE_SHA"
test "$(sha256sum "$MANIFEST" | awk '{print $1}')" = "$EXPECTED_MANIFEST_SHA"
origin_url=$(cd "$SOURCE_MAILBOX" && git config --get remote.origin.url)
test -n "$origin_url"

if [[ ! -e "$CLONE" ]]; then
  git clone -q -b hpc-mailbox --single-branch --no-checkout "$origin_url" "$CLONE"
elif [[ ! -d "$CLONE/.git" ]]; then
  echo "existing retrieval clone path is not a Git repository: $CLONE" >&2
  exit 161
fi

cd "$CLONE"
test "$(git config --get remote.origin.url)" = "$origin_url"
git config core.autocrlf false
git config core.safecrlf false
git config core.sparseCheckout true
git config user.name 'TUKF06 Evidence Bot'
git config user.email 'tukf06-evidence@localhost'
printf '%s\n' \
  '/inbox/kalmannet-tukf06/' \
  '/outbox/kalmannet-tukf06/' > .git/info/sparse-checkout
git checkout -q hpc-mailbox
git fetch -q origin '+refs/heads/hpc-mailbox:refs/remotes/origin/hpc-mailbox'

remote_spec="refs/remotes/origin/hpc-mailbox:$RELATIVE_ARCHIVE"
if git cat-file -e "$remote_spec" 2>/dev/null; then
  remote_blob=$(git rev-parse "$remote_spec")
  test "$(git cat-file -s "$remote_blob")" = "$EXPECTED_ARCHIVE_BYTES"
  test "$(git cat-file blob "$remote_blob" | sha256sum | awk '{print $1}')" = "$EXPECTED_ARCHIVE_SHA"
  echo "TUKF06_ISOLATED_BINARY_EVIDENCE_ALREADY_PRESENT commit=$(git rev-parse refs/remotes/origin/hpc-mailbox)"
  exit 0
fi

DEST="$CLONE/outbox/kalmannet-tukf06/artifacts"
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
    cp "$source_path" "$destination_path"
  fi
}

copy_if_absent_or_verify "$ARCHIVE" "$DEST/$NAME"
copy_if_absent_or_verify "$MANIFEST" "$DEST/package_manifest.json"
copy_if_absent_or_verify "$CHECKSUMS" "$DEST/package_checksums.json"
test "$(sha256sum "$DEST/$NAME" | awk '{print $1}')" = "$EXPECTED_ARCHIVE_SHA"
test "$(wc -c < "$DEST/$NAME")" = "$EXPECTED_ARCHIVE_BYTES"

attribute=$(git check-attr text -- "$RELATIVE_ARCHIVE" | awk -F': ' '{print $3}')
if [[ "$attribute" != "unset" ]]; then
  echo "archive text attribute was not disabled: $attribute" >&2
  exit 162
fi
git add \
  outbox/kalmannet-tukf06/artifacts/.gitattributes \
  "$RELATIVE_ARCHIVE" \
  outbox/kalmannet-tukf06/artifacts/package_checksums.json \
  outbox/kalmannet-tukf06/artifacts/package_manifest.json
archive_blob=$(git rev-parse ":$RELATIVE_ARCHIVE")
test "$(git cat-file -s "$archive_blob")" = "$EXPECTED_ARCHIVE_BYTES"
test "$(git cat-file blob "$archive_blob" | sha256sum | awk '{print $1}')" = "$EXPECTED_ARCHIVE_SHA"

staged=$(git diff --cached --name-only)
expected=$(printf '%s\n' \
  outbox/kalmannet-tukf06/artifacts/.gitattributes \
  "$RELATIVE_ARCHIVE" \
  outbox/kalmannet-tukf06/artifacts/package_checksums.json \
  outbox/kalmannet-tukf06/artifacts/package_manifest.json)
if [[ -n "$staged" && "$staged" != "$expected" ]]; then
  echo "unexpected staged retrieval paths in isolated clone" >&2
  printf 'staged:\n%s\nexpected:\n%s\n' "$staged" "$expected" >&2
  exit 163
fi
test -z "$(git diff --name-only)"
if [[ -n "$staged" ]]; then
  git -c core.autocrlf=false commit -q -m 'hpc-mailbox: return TUKF06 binary evidence'
fi

git fetch -q origin '+refs/heads/hpc-mailbox:refs/remotes/origin/hpc-mailbox'
git rebase -q refs/remotes/origin/hpc-mailbox
git push -q origin HEAD:hpc-mailbox
git fetch -q origin '+refs/heads/hpc-mailbox:refs/remotes/origin/hpc-mailbox'
remote_blob=$(git rev-parse "$remote_spec")
test "$(git cat-file -s "$remote_blob")" = "$EXPECTED_ARCHIVE_BYTES"
test "$(git cat-file blob "$remote_blob" | sha256sum | awk '{print $1}')" = "$EXPECTED_ARCHIVE_SHA"
echo "TUKF06_ISOLATED_BINARY_EVIDENCE_PUSHED commit=$(git rev-parse refs/remotes/origin/hpc-mailbox)"
echo "archive_sha256=$EXPECTED_ARCHIVE_SHA"
echo "archive_bytes=$EXPECTED_ARCHIVE_BYTES"
echo "package_manifest_sha256=$EXPECTED_MANIFEST_SHA"
