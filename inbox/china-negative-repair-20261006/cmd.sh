#!/bin/bash
set -o pipefail
timeout --signal=KILL 30s bash <<'METADATA_BODY' 2>&1 | LC_ALL=C awk '
BEGIN { n = 0; truncated = 0 }
{ s = length($0) + 1; if (n + s > 30000) { truncated = 1; exit 45 }; print; n += s }
END { printf "TOTAL_OUTPUT_TRUNCATED=%d\nTOTAL_OUTPUT_BYTES=%d\n", truncated, n }
'
set -e -o pipefail
export LC_ALL=C
printf 'US_RESULT_METADATA_BEGIN\n'
base=/data1/home/sunyiq/forcing_swap_daily_2026_09/runs
check_dir() {
    test -d "$1" && test ! -L "$1" || return 31
    test "$(readlink -e -- "$1")" = "$1" || return 32
}
check_dir /data1/home/sunyiq
check_dir /data1/home/sunyiq/forcing_swap_daily_2026_09
check_dir "$base"
for seed in 100 200 300; do
    run="$base/fswap_armE23_s${seed}_2026_0908_1745_ep30"
    check_dir "$run"
    before=$(stat --printf='%d|%i|%s|%Y|%Z|%h|%f' -- "$run")
    printf 'RUN=%s|%s|%s\n' "$seed" "$run" "$before"
    for relative in train_data test test/model_epoch030; do
        target="$run/$relative"
        if test -e "$target" || test -L "$target"; then
            check_dir "$target"
            printf 'DIR=%s|%s|PRESENT|%s\n' "$seed" "$relative" "$(stat --printf='%d|%i|%s|%Y|%Z|%h|%f' -- "$target")"
        else
            printf 'DIR=%s|%s|MISSING\n' "$seed" "$relative"
        fi
    done
    for relative in config.yml model_epoch030.pt train_data/train_data_scaler.yml test/model_epoch030/test_results.p test/model_epoch030/test_metrics.csv output.log; do
        target="$run/$relative"
        if test -e "$target" || test -L "$target"; then
            test -f "$target" && test ! -L "$target" || exit 33
            test "$(readlink -e -- "$target")" = "$target" || exit 34
            printf 'FILE=%s|%s|PRESENT|%s\n' "$seed" "$relative" "$(stat --printf='%d|%i|%s|%Y|%Z|%h|%f' -- "$target")"
        else
            printf 'FILE=%s|%s|MISSING\n' "$seed" "$relative"
        fi
    done
    test -f "$run/config.yml" && test ! -L "$run/config.yml"
    test "$(stat --printf='%s' -- "$run/config.yml")" = 1785 || exit 35
    cfg_sha=$(sha256sum -- "$run/config.yml")
    printf 'CONFIG_SHA256=%s|%s\n' "$seed" "${cfg_sha%% *}"
    after=$(stat --printf='%d|%i|%s|%Y|%Z|%h|%f' -- "$run")
    test "$before" = "$after" || exit 36
    printf 'RUN_AFTER=%s|%s\n' "$seed" "$after"
done
printf 'US_RESULT_METADATA_COMPLETE\n'
METADATA_BODY
codes=("${PIPESTATUS[@]}")
printf 'QUERY_EXIT=%s\nLIMITER_EXIT=%s\n' "${codes[0]}" "${codes[1]}"
test "${codes[0]}" -eq 0 && test "${codes[1]}" -eq 0
