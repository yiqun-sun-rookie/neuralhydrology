#!/bin/bash
# ID29 seq=249: deploy and submit the 20-coordinate isolated numerical audit.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
WRAPPER_REL=src/29_nearing2022_da_ar/hpc/run_partial_registered_results_audit_seq249.slurm
TEST_REL=test/test_nearing2022_partial_audit_seq249_slurm.py
PREFLIGHT_REL=results/29_nearing2022_da_ar/formal_closure/partial_registered_results_audit_seq249_preflight_20260812.json
WRAPPER_SHA=3bdd38d9bcbbcaf43cdf85a1352e0b30a639a64da0c462c55e5ca946dfdffdb6
TEST_SHA=8fdb59ef7f2a018a145dfcf71b837ea6953a278e909f824b7906c88c83c3c8a8
PREFLIGHT_SHA=9bbb84f08d5271b3830646aff27d944333e7be63457bd91c8e9f35b74031b79f
AUDITOR_SHA=7c99332b785a2a088961b51e6085fada72294ce4f8e98ed05663818660f35725
REGISTRY_SHA=37b312dbd362399a9771f2233d1e1139ea25d5339d1bbc7a806fa75be30b9215
ACCEPTANCE_SHA=6125cab8935c3ad0ab498865c661c47ea83c837c7627dff2534ba5a5b9185895
FINAL="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/partial_numerical_audit_seq249_v1"

deploy_payload() {
  relative=$1
  expected=$2
  target="$ROOT/$relative"
  temporary="$target.preparing-seq249"
  mkdir -p "$(dirname "$target")"
  test ! -L "$target"
  if test -e "$target"; then
    cat >/dev/null
    test -f "$target"
    test "$(sha256sum "$target" | awk '{print $1}')" = "$expected"
    echo "already_exact=$relative"
    return
  fi
  test ! -e "$temporary"
  base64 -d | gzip -d > "$temporary"
  test "$(sha256sum "$temporary" | awk '{print $1}')" = "$expected"
  mv "$temporary" "$target"
  test "$(sha256sum "$target" | awk '{print $1}')" = "$expected"
  echo "deployed=$relative"
}

deploy_payload "$WRAPPER_REL" "$WRAPPER_SHA" <<'B64'
H4sIAAAAAAAACrVZW3PbNhZ+x69AUHcipaIoKbZja8rOuLGbuJvGGdvtbsbVcGDyUEJMAgwAyla93t++AxCkSN2Strt5cCjwOxccHJwbv3nm3zLu31I1Q99c/Xhy/fot9rxP4tbjNIPg/Wjk5VRqjxYx08cNiFllmgkezKZ5sd8zf4/s31EDBQ9RWsQQ8GkxHOw3XnARgwqGzRVN1V17KcoL5eUgPfOq9UazDILBcDwYjAeDxroodF7owI+ppkN/JjLwVcEX7LPPgUrGp6PBaBTG1I9SoQoJ4WgwOhwcDQd+KqbK//Yh/PZTXxS6uQUphfybHEFKhBRo7IHAOcshoSxF6PLi4vrLnNH56dlJQPYM2lcy8kfHYRsRUknQ5dmb86vry48B2TMEvoQpU1ouCDp58+by7M3J9fnF+4rNmrJ0OpUwpeZACTo9P3nz/uLq+vx1aFV0RBJUkWq1Ub6fCJnRNHSM/ZjRKRdKs0gRdPLr6fn1xWWlmYoky7XyrU+F1pFoGpb6goQ4dIL6+YKgq7N3P1WEszzyZcF3kIQlTwWfR/vHfZUWMiPop/P3J+8CsreyLb9iw4sMJIto2qIO50OC/nlx+Y+A7FkO/VxCbrft7V29+/Xyl/Dnix/D81OCrk8u35xd28ty9tvJO+/6yjs98d4N9r3rs+Fg4F0N0Nm/Ppy9vj47DZ0twqu3J6ODw+BVdHz88uXo9tXRAR3RwdHR8eHw9mAIh4Ojg4TG9NVodLwfwX5yBMdHEA8ODg9fHg2PDg8HycuDV6MDhDQojZ9hD7DTk7SWzA7cCtnrJIzHeM0SBHsZfYgh1zM8xPbm4+dftE7DHi+e498Rxl4uGdfY+1ww3SU4wMRJ9hJM9tzOm0vmcJfqvlsDucUGjOx11IyODg5VkTXg+N+Y3t/h54+lBnvDp+elAntbDE8Qyu5iJmsLISUKGQH+j58xziLBY/rSBx35uRQJS6Ef+3axr2bIPmAaaTanGjCfhQnjNEWRsa01KIKHXEiNP3y8fnvx/sPJ9Vt3ifYel0vj78Z7y19PBKF8oWeCY69ig0vHN/9X19s8Ny60+Vm6H3Fb8aVIIVSc5momdP+TEpzg779//uHjc5RIkeEwTAptLn+IWWa1pJwLbe++QsitGboSn1M9S9ltBf5A9awCqcWSIKc8pgpThfMYISmExoEFd9RC9amczm+Gk25fghLpHDpdxGKga5BRC1LFsDXYyxasEbzWkPstpKZyCkax+v3BBJVJY43ycNJF5ofZf59xBVJ3Bj2stOxY1X1MXCQj3S4qbVVpAhtiU2XA1qvCGflLsbAmjkSWp2AEiBSUOyF7ESGEOU0LawbDuCJxuw9LB1+KnINkyaIpywXvWlYGWrJIhcYCPafiOhwhLSnjjE9xgPO4L4HGYaTmnfr0fEzgIQfJMuAVB7noR2pOevgOIA9jSGiR6pDT4CeaKujhWC9yCJSWXbTcltolobH5PyuhsjuLjYRHe8QaspvB5MbyDVlMJl2cCInNOmZ89SA6xuF7uLJEDzeU7j6hyrLBVit2EMYYWy7l09cYbx25zQhrSKoUy1haYmeLHGROJc1Ag9xE2rxiLTlqM6DN0YC6KGNKMT6trGzJrJlJJISMGTf3xljavmka29nohjgWDsKSdXpzqGSCg6CpJEH1ETjpCnSnsYnWMXu4oamp21KINMQ4aB5qPxXRzWYORngZaCaIJTgF3ql4dPGzAA/H5WlQpgD/RtMCzkyN2UnI2UNeihIcHIvloUlx38OJKHiMH1s8n0gXSXFvd1Uu9ZnRbjBBJgwEqxFnzVeluDex1gQaHGBD45u1G1KuhSb/kQmSkIAEXsYQA1wLLJs4Gy4VHTzkpY2XvCyfJl8fE5Pp/UzEkIaQi2g2eDnwzdqyMCTI3rrajUhEecxi4wCR4AmbkrHbByl/9xdZ6jy1iZ1BdJcLxvUS35bbz/U6WSoa/Mvs0Tdra8BcQswi64FjY64i1WsYF2TJuB1vOyW86/BLG63wdMtrsO1sHaLbQ08IoRgSHINJZLfQMYixTYNd7P2AjZwbpWUPi9tPEOlJ6bg5XaSCxuP19/V5WGUMNzK2CdM8uq3YV/DAlDbK2eRa/uo0AUyVXucQ7ucqJGaygYiZXAWoRZYyftcAuZUK+FQFkpYiWMh1gnLz5p/S1FwUizDPnW79ytmmX+TmcDuP5HahwWzU4PpKh4r9AT1MMtPBhrz5plp6KrlJ0IXkFUOEkHta+ryKZpBRMsak0Y55Ji8VGmyH7VVJyjPXxauKQm8+rHzVtkjhJ3Fr7uUYh2GZ+8OwQ4Qi3T7wOZOC35BWxzNpURtJO2j7U9Cdkv40fH9xevb+5JczUjl2GeXI2IU7t1ol5DrJRqKwl9QEvka2rrhUwX0jvhH5K3zFImO8UFUKNmchpIa4KQF7VfbZJK+kd/AlfTPXeHiDvuVm63qvUrs2g0l6DbI21epmW1QN0W0qGzDJGD+a9m7cvvNlaWNe9KxXG0YW3zf5VXW6T3V8qRNJRrVkD2EmYpYwMM5T1lUlMJHiD+AhjSLINbUBaQ345Crv/r1kJnPDg+6YtqMfF1muOs7fe5jxGLgORj1r3vAOFiq4lgV08XeY/M5JDwOPRMz4NCCFTrwj0kW2D9zIbYVH16To5nk/C5o23JqqXzdvVlnVCalwzBSdSoAxfnQSTXZ2VUDTEfD3eDTYyb0wraWIASsAhRO4B4n1jHI8GuDq6PGy8lFrIrkwXZldudnqcZOv0yEWoCxDBYD1rK5OqKp1acv/8LFuZxttuudJyIVnu8Oqx62mdlX/WlbIQ9e52rmCl1GW3ooHT8HnwlYNo/1js8w4y4qsDnPGND+0+Sgdi6Jm97dUGv1vVXLsUJTlm7e+Sfg6ur3B3ZKo3mmcKG8apoX8wpTOUtoxTT2F+PNzuub4ww5lqrGF60dnVJlBRGtC4Z6F+rpZxb2Qd5vGElUhxKag9GoZpLQcN1Oy06NfDqIsumxJba7vdLv9GTw4VoZzayCDA6t439wT1elYhXxMNgxtzNyCxmVYXAtwXeR8ZQu/lid9FafRTk6jr+LEEtffDk0YdZRbAgy5hByoaXacm+B60lhSmmCaJCBJk6/p9eoUX4c+MtkdTj84CZaJ6agkKAUxvoVU3O+Ip07o0wYVqGTKdNni3kivd7tdwRf41TZLtNWrQ+2Mzk3wnwPHroTHOciGiitq7UjOE1PR1sAdyXlbOlgzoblTClNc8vIYN+GyZBOVPbdVruXXN9vquq8x4FY3Mvm3vl2Ux6t+hK2MpTMhCRGwXH+pkHa6ejW78iOYBw8QFWaHnmO0vZwW6s8U0Ev07pLZZZ6wyjxkbHJPVZluMt74S8ZtEDcde7zD5x0J4zGbs7igaahFCtK6k/m8Vci24N3ApQa1VuE907ONrLaDmhspNFjLhi0fDMuoTUz3aiP0rgjsuFUzu1yKuLCttw31ITN1qfEMMsammGzBt8lpR+b/T11dC6t9NXS+WoXxRsltGTcqZYf8K3U3MnNwVg5mbibINBVVO+E6I6NYX05TcdshL0jXNdVV/7253d4e0MsbiV2xFgmuKeMmKhkWth7VMxO8V2SUowQbK+yS/eD1LMDEcE1opMOMcpaAcuZaqmI316d5DjzuLEcdzXGHKwfMZHUOoRZ2y90+VWEuFHtoTigsWTUgaEwT6jlBG7nqUStDlacuqtT+q6Gtom9ENLPjVjdtTVD3sULTtKx7TPdbZOXc3G1q0hritgjtDzIuF1suu+UMdrpsBf2LPpuvNov1FVhrFtegj6QSvv3Gb9nR0wb+pm1a+VhblsKeGWzjdOM31uYXUYv2X6BsXpPW34Uhmgljek7ToFr7L1yx3QEBIgAA
B64

deploy_payload "$TEST_REL" "$TEST_SHA" <<'B64'
H4sIAAAAAAAACsVWS2/jNhC+61ewbAHbQKTaQpLGi+rgJt4mQLAxbPcBGAZBkyOJC4nSktQmbtH/XkiUYyuRbW0vPUmcxzcPzgxHpHmmDIqpjhOxcYQ9ftaZdEKVpSinpmSgmjGjJnYcZz6dPZH509MSBRWpT0goEiBk4CnQWfIV+gMvpwqk0avR2pn8dvewfJqjAO01f0RYK4bLrz8mEqgSMvKHvk84JVRVDM2UyI2u/mnBhSE5VUbQhCiIhDaggBMFukiM9vItdmbz6d30drpYVMb6DkJob7I61WZ3/62md8w43wuqQp4wTqx3Gr74l1eeTgqVYmfg/DGfzGbT/8+V8d6V2Xz68fHh1/vlcWdqgG4OhZlKaUJYkulCwSu5o18kVxAmIooN8Yf+9fBm5Htl0ZWeOg6HEBnQr8IspjICTTKZbIngII0wW2KoisAQKjlhWZonYICwrJCmP/hQuZMr4MBA60yVdbovDU8B5cTAi+mDZBkXMgpwYUL3Bg8qTVaosnZRgOobPKshq3SIv4CjYKfuKcgTyqCPv1/8Mlne3iPX/ZxtXElTCD75vlsmy63SMsYX6LxUq7H9YW+vVJv+Pnl0lwv3buI+Di/d5XQ0HLqLYWmolT386apkd7Rgb6YEszXfVc91UyqSTfbiavhSgGSAapxWTlfcHq6VyU4ZfyiBexfoCOuq19HjEJ5BIRNTifwqeweE0bhr3AnI/q43BNcD9HON1sLojuq6qZAiLVJ31wE1agujM2rPNupohQ/aKlNcSGpA43XlepnY83KjcdcsK4gUaA0cbSDJnusw3lJfY6BagzIN2OCw31uGiNCE5YWdISEVdnQBr+YHvLCk4KCJjIrR8HI3QMp+/4YZUDt10Mc1bmBhMRKywjwinUKKkczMGbEyJUGUF0dly7NnJ+GRfkPthTMos+gfQh3rq4tem+FemW/0HXIB4R8+PnyaPOJWuddXQhYpKMFo0nwcvo7aU6U31LD4eI5UilwVNvnvC2EjJNfExEAKaV8W/taRTP3XErDapNynULBbqzwdU//qul+vQRZlszWg+4OBF8MLFxFo02+UUYinf86mt8vpHan1yOJ+4l9dB38fWvkHnwh1/8rugxaSKUhBGpoQo0QUgap6QDNRPqyhYGSTFZJTtT14SC0MCqrV0EsyynX/daU4lRYbU20IBXusFa6JeN0oXktcvS+8dVWdlzet0nYZsDInn79W7YNt5cgsK00P7W5QlUwzEi1klAAJKSuvxUo0w7K0FT6YUSdMjcZtunXLnnfxjR7lvArsjfDqZJ6s9zndVnfdDHdHbYb4rcVejewaaWXX+0zh9QpbgJPgjX48D/6saJ7De/Bdob+5zfed0HRmR13hd3OjvnyO10ho9JEmGto1UzBKMN1ZnjIGuaGSATGxAh1nCe+ufVDgKTVKvLRp/gt3BntzDA4AAA==
B64

deploy_payload "$PREFLIGHT_REL" "$PREFLIGHT_SHA" <<'B64'
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
B64

test "$(sha256sum "$ROOT/src/29_nearing2022_da_ar/scripts/audit_partial_registered_results.py" | awk '{print $1}')" = "$AUDITOR_SHA"
test "$(sha256sum "$ROOT/src/29_nearing2022_da_ar/registry/evaluation_registry.csv" | awk '{print $1}')" = "$REGISTRY_SHA"
test "$(sha256sum "$ROOT/src/29_nearing2022_da_ar/reference/reproduction_acceptance.json" | awk '{print $1}')" = "$ACCEPTANCE_SHA"
test ! -e "$FINAL"
test "$(find "$(dirname "$FINAL")" -maxdepth 1 -name 'partial_numerical_audit_seq249_v1.preparing-*' -print -quit)" = ""
bash -n "$ROOT/$WRAPPER_REL"

python - "$ROOT" "$WRAPPER_REL" "$TEST_REL" "$PREFLIGHT_REL" "$WRAPPER_SHA" "$TEST_SHA" "$PREFLIGHT_SHA" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
rows = list(zip(sys.argv[2:5], sys.argv[5:8]))
for relative, expected in rows:
    path = root / relative
    assert path.is_file() and not path.is_symlink()
    assert hashlib.sha256(path.read_bytes()).hexdigest() == expected
preflight = json.loads((root / sys.argv[4]).read_text(encoding="utf-8"))
assert preflight["trigger"]["mailbox_sequence"] == 248
assert preflight["trigger"]["target"] == "N22-EVAL-TS-DA-L04-TE100-S0"
assert preflight["trigger"]["registered_complete_coordinates"] == 20
assert preflight["single_factor_change"]["predecessor_complete_coordinates"] == 19
assert preflight["single_factor_change"]["minimum_complete_coordinates"] == 20
assert preflight["single_factor_change"]["added_coordinates"] == [
    "N22-EVAL-TS-DA-L04-TE100-S0"
]
assert preflight["single_factor_change"]["excluded_nodes"] == ["ngu104"]
assert preflight["single_factor_change"]["other_scheduler_resources_changed"] is False
assert preflight["execution_contract"]["minimum_complete_coordinates"] == 20
assert preflight["scientific_boundary"]["numerical_auditor_changed"] is False
assert preflight["scientific_boundary"]["acceptance_thresholds_changed"] is False
wrapper = (root / sys.argv[2]).read_text(encoding="utf-8")
assert "#SBATCH --exclude=ngu104" in wrapper
assert wrapper.count("--mailbox-sequence 249 --minimum-complete 20") == 2
assert "#SBATCH --gres=gpu" not in wrapper and "#SBATCH --mem" not in wrapper
parts = wrapper.split("<<'PY'\n")
blocks = []
for part in parts[1:]:
    block, marker, _ = part.partition("\nPY\n")
    assert marker
    compile(block, "<seq249-slurm-heredoc>", "exec")
    blocks.append(block)
assert len(blocks) == 2
print(json.dumps({
    "deployment_hashes_verified": 3,
    "compiled_python_heredocs": len(blocks),
    "excluded_node": "ngu104",
    "minimum_complete_coordinates": 20,
}, sort_keys=True))
PY

JOB_ID=$(sbatch --parsable "$ROOT/$WRAPPER_REL")
case "$JOB_ID" in
  ''|*[!0-9]*) echo "Invalid Slurm job id: $JOB_ID" >&2; exit 1 ;;
esac
echo "submitted_job_id=$JOB_ID"
scontrol show job -o "$JOB_ID"
sacct -n -X -P -j "$JOB_ID" --format=JobIDRaw,JobName,State,ExitCode,Elapsed,Reason
echo "registered_matrix_modified=false"
echo "frozen_acceptance_modified=false"
