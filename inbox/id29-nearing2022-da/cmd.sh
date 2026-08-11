#!/bin/bash
# ID29 seq=188: deploy the fail-closed replacement verifier Slurm wrapper; submit nothing.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
TMP=
trap 'test -z "$TMP" || rm -f "$TMP"' EXIT

deploy_gzip() {
  target=$1
  expected_bytes=$2
  expected_sha=$3
  mkdir -p "$(dirname "$target")"
  if test -e "$target"; then
    test -f "$target"
    test ! -L "$target"
    test "$(stat -c '%s' "$target")" = "$expected_bytes"
    test "$(sha256sum "$target" | awk '{print $1}')" = "$expected_sha"
    echo "already_matching|$target"
    return
  fi
  TMP="$target.tmp.seq188.$$"
  test ! -e "$TMP"
  base64 --decode | gzip -dc > "$TMP"
  test "$(stat -c '%s' "$TMP")" = "$expected_bytes"
  test "$(sha256sum "$TMP" | awk '{print $1}')" = "$expected_sha"
  chmod 0644 "$TMP"
  ln "$TMP" "$target"
  rm -f "$TMP"
  TMP=
  test -f "$target"
  test ! -L "$target"
  test "$(sha256sum "$target" | awk '{print $1}')" = "$expected_sha"
  echo "deployed_additively|$target"
}

echo "=== SNAPSHOT TIME ==="
date --iso-8601=seconds

deploy_gzip \
  "$ROOT/src/29_nearing2022_da_ar/hpc/run_warmup_target_replacement_verifier.slurm" \
  6299 ad013f8b8618d4762a092a0a0b28f92248a7c3c8dd6b00679e633055338c24a2 <<'PAYLOAD'
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
PAYLOAD

deploy_gzip \
  "$ROOT/test/test_nearing2022_replacement_verifier_slurm.py" \
  1571 c078681dbd82573c2ea2a5585cfe2fb3103fbfa5cf2449643317aea91ca9992c <<'PAYLOAD'
H4sIAAAAAAAACp2U3WvbMBDA3/1XaKIPDixuYmjZAn4orcvKuiVkYR0sQyjW2dZqS97pnCaM/e/DTtLWJP3Y/CJz97sv3elStCWrJOWFXjBdVhaJTSTlnudN48lYTMfjGYtakS9EqgsQohcgOFsswe8FlUQw5L4Pf3g307PJJJ6yiD1YHjPuMOHNGb4XBiRqk4WDMBRKComtIq82ANZG3Eks60qQxAxIIFSFTKAEQ2IJqFMNGLiixpJ7nqcgZQTuMCZaTGgnUqkLkRTWgRLSKGGsEXYJeIeatMn83shjjDGCFbGIbYsIEKQSjcwHk1ilTRbxmtL+O95rcYRftUZQLGJ+K2g+3qTD3rA+sDk/urz6fHY95/ztE/qb8fTjAfWcHzmSBHPOInY+/jS5jmfxxSEMVppEYtUGHYwGj6FdgsLVi1I7p60RCiowCkyynvMRm3OZEqC9HYWD8GQ47OYikXQqk92NJpIaD8Pgp7PmZS7c45Ky2hV9/JzvOX8B27juJvuyc0fK1vTaGFv6UKhKahRYGwMopJIVbSwqwFITgWpudoY17NkQSm20yR43pGN1KQvXMUPItCNomlhKQr0SpVXNdB/G70sppdEpONrrQbl8mLv9Cd0MtnQOkJgsCr+UeAvItNk8jtQiexDt5qtjxd1CUpJzZizt7Dr6fj9DcFFW1U8zWLI+pl396177QhvlBOXQTHph16AeiFy6/D/f+nLr4583m0tQV+Ta/9bJ+pkFl+RSm6Ba8zbmdhU3WRd64bUyWFWQULtztvLA5TI8OfXvl2NbymJN4PxeL8hhpXQGjvxOl1Ief5vE57P4QnyNp1eXV/FUfPlwFp6cRr93Mf7w+7v/C1d9n18jBgAA
PAYLOAD

deploy_gzip \
  "$ROOT/results/29_nearing2022_da_ar/formal_closure/warmup_target_replacement_verifier_slurm_preflight_20260811.json" \
  3231 f537464bcfefe1899ebced35362526504ad8398af48b2260b2bb5833aa53c634 <<'PAYLOAD'
H4sIAAAAAAAACp1WTY/jNgy9z68QfO14xh9xYufabk8tWqB7KFAsBFqiYs3IkleSJ+Mu9r8XkuN8TWa32GMcUiQfHx/55Y6QxLEOe0i2JNEIVupdkRVFugfbj0Pqwe7QpxYHBQx71D59QSuFRJs6Ndo+HSwKJXedT1/y5D48yCyCR07Bh0eLrFinWZ3m+cc83+arbVX8lNXbLJuNnQc/umBoEfhEtfGU46DMhDz+cGPbS++RH+yZGTCY/wpSpUwZh5z8FTIh+Ips9NJoYgTxHRKpOQ6oOWpPzitgHUhNljoICI+WtMZ3RIxKpVWZn5uTJ9M64kbGEPnDnAWMvjNW/gshHG3NqDnYKdmSL3eEEJIMIC1yOlgcwKKlveEhFk+2RIByeH9hZket3zc6S4WGVN6zc2hf0NIBJmWAH0G8spqrZnPiT6Y9w/dtbtRbkFrq3btWFnfSeQxV9OCtfH2T3R0hXyNmsh9UrCLGPmEVaUQH8F1oq7PssWjoGRUpBwr2sRvYox01nYlJZ2LSc3CWhj7EF2Ojjs+3k8fAsnXRNBd/uA6Kah0iA8/yUtRtvc5rvtqsC8iaAjLI2qIWTVGsatiwktWcr9ssW28aXJdlVlVlWbNiBcUS0KPzx3LCj8f45byiW1nTmM/DMF28s+SdV5v8/PspbZZt6nWd85bXRbUpWYFQQFXVFRNYiLbMs1K0AiomitWqWa/KMt8AQpMzaJqmYEu4SOJTNt/th2NWDt49Ro/pG22J03ZW11WgUyVZy6BlzVo0uMkKUZT5ZrVeiVxkeVGyouGrhldiIzLRbArIM4QSs7xtRV4LbOpNcqRakDQ+KrR0Bx5PVLsaJSp5wPafoFFVniX3Ua2qPE8+Hen9eYwjGvnvXBiaRVNYmPckiod53h4cD36fR7QyTDYyYzk9iha+AvMkaMKsK2Q2cERY0xMHjHmS/p28ie7nMpKf//j9z98+fPzwyxsTfJWeMsOjWbad1TWIcYfsGTltURiL1Ix+GD3l0iLzxk40ivU8j96Oy1iz0YYUqUVQEUN60ulRP2uzj+LhqPNSKRoACSpxgoaCpwoCUTUMrjP+1BywXgpg/qo3R0LYUYc4xWWFLo4ClUHMJQMVoMVAwMvE37N2HoJE8wMA7zih9naiFwnSAZyLanbh8ITMO/qe+s3yeulzQH6ZK4tuVN7dni1hbA+Khu02WnzkEnbaOC+Ze/ye/B2U/bCLY65idKG2V+l8aJKQGhQ1lu6NfV7yuVGcm/rWKMmokvr5Cua9lR7dCaketBTornAdxlZJ18VuUAc9UiEVusl57KlFDT0eHI7keDJSXzMjbqLDjgQOw7xA6IB2XknUaDXROIixW1dJvN1j8xwf/X98pb2AkvxqnWnc0yjRzPQ96OCUDJPvjCZpT4ag5578wFog6eelpUsIdyLnMi3CsNEh/7Hg1vCRRWyZ0d4C8yHubfMDDwO67xu9WQOnHf2/fL4FwlLpFRD1siYFSBW/ZAtnwQYKBHpUCzciNAGsQarbo96C66ibtIfXm//38Cr7sQ9DglSh3sVxyosl6tn3G3pyZBJHJgMrQ8M+dkhCSqPHNIwn2cFApCOHY1cZBkpNDyTY7S0MA9rwtzaeLEcfMZYcT7Z7AprHgzjIOYkjRqLUkZARsdiD1Mf3R+1lsGodmfdidJ/32+FKllq6bj6JnQs383QW4nQ4L/LgSCia+L0hQZbToyxfXOjHezwsgIfk7uvdf5rug9mfDAAA
PAYLOAD

echo "=== DEPLOYED HASHES AND STATIC SYNTAX ==="
sha256sum \
  "$ROOT/src/29_nearing2022_da_ar/hpc/run_warmup_target_replacement_verifier.slurm" \
  "$ROOT/test/test_nearing2022_replacement_verifier_slurm.py" \
  "$ROOT/results/29_nearing2022_da_ar/formal_closure/warmup_target_replacement_verifier_slurm_preflight_20260811.json"
bash -n "$ROOT/src/29_nearing2022_da_ar/hpc/run_warmup_target_replacement_verifier.slurm"
test "$(sha256sum "$ROOT/src/29_nearing2022_da_ar/scripts/verify_warmup_target_replacement_chain.py" | awk '{print $1}')" = \
  0bcabc96f9e702f2317464f1f0123c29d49d5f7f0f972a10ea3e01bbf18fe987

echo "=== FROZEN PAIR BOUNDARY ==="
test "$(sha256sum "$ROOT/src/29_nearing2022_da_ar/scripts/prepare_warmup_target_pair.py" | awk '{print $1}')" = \
  31f856df60b0daacea873386880581f975480c842fae0d605a5abe4b40a1b664
test "$(sha256sum "$ROOT/src/29_nearing2022_da_ar/hpc/run_warmup_target_pair.slurm" | awk '{print $1}')" = \
  5c1d6a6f260440bd67d23ea2612c1ce9d28393684952c5978d1ddb103d27f804
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = '202293|PENDING|JobHeldUser|N22-manifest'
echo "paired_preparer_modified=false"
echo "paired_runner_modified=false"
echo "verification_job_submitted=false"
echo "pair_training_submitted=false"
echo "registered_matrix_modified=false"

echo "=== REPLACEMENT JOB STATES ==="
sacct -n -X -P -j 202510,202511 --format=JobIDRaw,JobName,State,ExitCode,Elapsed,Start,End,NodeList
squeue -h -j 202510,202511 -o '%i|%j|%T|%M|%R|%E' | sort
