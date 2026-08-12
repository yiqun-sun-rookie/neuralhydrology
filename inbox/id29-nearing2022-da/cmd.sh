#!/bin/bash
# ID29 seq=275: deploy and submit the 22-coordinate isolated numerical audit.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
WRAPPER_REL=src/29_nearing2022_da_ar/hpc/run_partial_registered_results_audit_seq275.slurm
TEST_REL=test/test_nearing2022_partial_audit_seq275_slurm.py
PREFLIGHT_REL=results/29_nearing2022_da_ar/formal_closure/partial_registered_results_audit_seq275_preflight_20260812.json
WRAPPER_SHA=bbfe5d02971ae965c489a26583d98ecc7ea596ec8e17d4318972e15825f86598
TEST_SHA=c7a7a93445cfeea54fdec84d6201ebc6670a5bcfe2a2fa6e4505974d13b6d109
PREFLIGHT_SHA=ee06304c0b75bfdcb2985146ddca118b9e04692596f76f0a6bc4ed927ba1de44
AUDITOR_SHA=7c99332b785a2a088961b51e6085fada72294ce4f8e98ed05663818660f35725
REGISTRY_SHA=37b312dbd362399a9771f2233d1e1139ea25d5339d1bbc7a806fa75be30b9215
ACCEPTANCE_SHA=6125cab8935c3ad0ab498865c661c47ea83c837c7627dff2534ba5a5b9185895
FINAL="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/partial_numerical_audit_seq275_v1"

deploy_payload() {
  relative=$1
  expected=$2
  target="$ROOT/$relative"
  temporary="$target.preparing-seq275"
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
H4sIAAAAAAAACrVZW3PbNhZ+x69AUHcipSYpKbHjaMrOuLGbuJvGGdvtbsbVcGDyUEJMAgwAyla93t++AxCkSN2Strt5cCjwOxccHJwbv3kS3DAe3FA1Q99c/nh89fot9rxP4sbjNIfw/WjkFVRqj5YJ08NhC2OWmWaCh7NpUb7YN3+P7N9RCwX3cVYmEPJpORy8aL3gIgEVthlyTdVtdykuSuUVID3zqvNGsxzCwXA8GIwHg9a6KHVR6jBIqKbDYCZyCFTJF+xzwIFKxqejwWgUJTSIM6FKCdFoMDocHA0HQSamKvj2Pvr2ky9K3d6ClEL+TY4gJUIKNPZA4IIVkFKWIXRxfn71Zc7o7OT0OCR7Bh0oGQejV1EXEVFJ0MXpm7PLq4uPIdkzBIGEKVNaLgg6fvPm4vTN8dXZ+fuazZqydDqVMKXmQAk6OTt+8/788ursdWRVdEQSVJlptVF+kAqZ0yxyjIOE0SkXSrNYEXT868nZ1flFrZmKJSu0CqxTRdaRaBZV+oKEJHKC/GJB0OXpu59qwlkRB7LkO0iiiqeCz6OXB77KSpkT9NPZ++N3Idlb2VZQs+FlDpLFNOtQR/MhQf88v/hHSPYsB7+QUNhte3uX7369+CX6+fzH6OyEoKvjizenV/a2nP52/M67uvROjr13gyPv6nQwOvAuB+j0Xx9OX1+dnkTOFtHl2+PRwWH4Mn716vnz0c3LowM6ooOjo1eHw5uDIRwOjg5SmtCXo9GrFzG8SI/g1REkg4PDw+dHw6PDw0H6/ODl6AAhDUrjJ9gD7PQknSWzA7dC9nop4wleswTBXk7vEyj0DA+xvfr46Ret07LHs6f4d4SxV0jGNfY+l0z3CQ4xcZK9FJM9t/P2kjncpbrv1kBusQUjez01o6ODQ1XmLTj+N6Z3t/jpQ6XB3vDxaaXA3hbDE4Ty24TJxkJIiVLGgP8T5IyzWPCEPg9Ax0EhRcoy8JPALvpqhuwDprFmc6oB81mUMk4zFBvbWoMiuC+E1PjDx6u35+8/HF+9dZdo72G5NP5uvLf89UgQKhZ6Jjj2aja4cnzzf329zXPrQpuflfsRt5VAigwixWmhZkL7n5TgBH///dMPH5+iVIocR1FaanP5I8xyqyXlXGh79xVCbs3QVfiC6lnGbmrwB6pnNUgtlgQF5QlVmCpcJAhJITQOLbinFsqncjq/Hk76vgQlsjn0+oglQNcgow6kjmFrsOcdWCt4rSFfdJCayikYxZr3BxNUJY01ysNJH5kfZv8+4wqk7g32sdKyZ1UPMHGRjPT7qLJVrQlsiE21ATuvSmfkL8XChjgWeZGBESAyUO6E7EWECOY0K60ZDOOaxO0+qhx8KXIOkqWLtiwXvBtZOWjJYhUZC+w7FdfhCGlJGWd8ikNcJL4EmkSxmvea0wswgfsCJMuB1xzkwo/VnOzjW4AiSiClZaYjTsOfaKZgHyd6UUCotOyj5bbULgmtzf9ZCbXdWWIkPNgj1pBfDybXlm/EEjLp41RIbNYx46sH0TMOv49rS+zjltL9R1RbNtxqxR7CGGPLpXr6GuOtI7cZYQ1JlWI5yyrsbFGALKikOWiQm0jbV6wjR20GdDkaUB/lTCnGp7WVLZk1M4mFkAnj5t4YS9s3bWM7G10Tx8JBWLpObw6VTHAYtpUkqDkCJ12B7rU20TlmD7c0NXVbBrGGBIftQ/UzEV9v5mCEV4FmgliKM+C9mkcfPwnxcFydBmUK8G80K+HU1Ji9lJzeF5UowcGxWB6aFHf7OBUlT/BDh+cj6SMp7uyuqiWfGe0GE2TCQLgacdZ8VYo7E2tNoMEhNjSBWbsm1Vpk8h+ZIAkpSOBVDDHAtcCyibPhUtPBfVHZeMnL8mnzDTAxmT7IRQJZBIWIZ4Png8CsLQtDguyta9yIxJQnLDEOEAuesikZu32Q6re/yDPnqW3sDOLbQjCul/iuXL/Q62SZaPGvsodv1taAhYSExdYDx8ZcZabXMC7IknE33vYqeN/hlzZa4emW12Db2TpEfx89IoQSSHECJpHdQM8gxjYN9rH3AzZyrpWW+1jcfIJYTyrHLegiEzQZr79vzsMqY7iRsU2Y5tFtxb6Ce6a0Uc4m1+pXrw1gqvI6h3A/VyEJky1EwuQqQC3yjPHbFsit1MDHOpB0FMFCrhNUmzf/lKbmoliEee71m1fONn5ZmMPtPZCbhQazUYPzlY4U+wP2MclNBxvx9pt66bHiJkGXktcMEULuaenzKp5BTskYk1Y75pm8VGqwHbZXJynPXBevLgq9+bD2VdsiRZ/EjbmXYxxFVe6Poh4RivR94HMmBb8mnY5n0qE2knbQ+lPQvYr+JHp/fnL6/viXU1I7dhXlyNiFO7daJ+QmycaitJfUBL5Wtq651MF9I74V+Wt8zSJnvFR1CjZnIaSGpC0Be3X22SSvonfwJX0713h4g77VZpt6r1a7MYNJei2yLtXqZjtULdFdKhswyRg/mPZu3L3zVWljXuxbrzaMLN43+VX1+o9NfGkSSU61ZPdRLhKWMjDOU9VVFTCV4g/gEY1jKDS1AWkN+Ogqb/9OMpO54V73TNvhJ2VeqJ7z933MeAJch6N9a97oFhYqvJIl9PF3mPzOyT4GHouE8WlISp16R6SPbB+4kdsKj75J0e3zfhK2bbg1Vb9u36yqqhNS4YQpOpUAY/zgJJrs7KqAtiPg7/FotJN7aVpLkQBWAAqncAcS6xnleDTC9dHjZeWj1kRyYboyu3K91eMmX6dDIkBZhgoA61lTnVDV6NKV/+Fj08622nTPk1AIz3aHdY9bT+3q/rWqkIeuc7VzBS+nLLsR956Cz6WtGkYvD8wy4ywv8ybMGdP80OWjdCLKht3fUmn0v1XJsUNxXmze+ibh6+juBndLonqnceKibZgO8gtTOktpxzTNFOLPz+na4w87lKnHFq4fnVFlBhGdCYV7FurrZhV3Qt5uGkvUhRCbgtKrZZDSctxOyU4PvxpEWXTVktpc3+v3/RncO1aGc2cgg0OruG/uier1rEIBJhuGNmZuQZMqLK4FuD5yvrKFX8eTvorTaCen0VdxYqnrb4cmjDrKLQGGXEAB1DQ7zk1wM2msKE0wTVOQpM3X9HpNim9CH5nsDqcfnATLxHRUEpSCBN9AJu52xFMn9HGDClQyZbpscWekN7vdruAz/HKbJbrqNaF2Rucm+M+BY1fC4wJkS8UVtXYk54mpaBvgjuS8LR2smdDcKYUprnh5jJtwWbGJq57bKtfx6+ttdd3XGHCrG5n829wuypNVP8JWxtKZkIQYWKG/VEg7Xb2GXfUVzIN7iEuzQ88x2l5OC/VnCuglenfJ7DJPVGceMja5p65MNxlv/CXjtojbjj3e4fOOhPGEzVlS0izSIgNp3cl83iplV/Bu4FKDRqvojunZRlbbQe2NlBqsZaOOD0ZV1Came7URelcEdtzqmV0hRVLa1tuG+oiZutR4BhljU0x24NvkdCPz/6euboQ1vho5X63DeKvktoxblbJD/pW6G5k5OKsGM9cTZJqKup1wnZFRzJfTTNz0yDPSd0113X9vbre3B/TqRmJXrMWCa8q4iUqGha1H9cwE7xUZ1SjBxgq7ZD94PQkxMVxTGusop5yloJy5lqrYzfm0KIAnveWooz3ucOWAmazOIdLCbrnvUxUVQrH79oTCktUDgtY0oZkTdJGrHrUyVHnso1rtvxraavpWRDM77nTT1gRNHys0zaq6x3S/ZV7Nzd2mJp0hbofQ/iDjarHjslvOYKfL1tC/6LPFarPYXIG1ZnEN+kBq4dtv/JYdPW7gb9qmlY+1VSnsmcE2zjZ+Y21/EbXo4BnK5w1p810Y4pkwpuc0C+u1/wJNdAW3AiIAAA==
B64

deploy_payload "$TEST_REL" "$TEST_SHA" <<'B64'
H4sIAAAAAAAACsVW227jNhB911ewbIHYQOTawiabLqoHN3GaAMHGsN0LYBgETY4kLiRKS1KbuEX/vaAoxXYsO0pf+mRrZs6ZC2eGFFmRK4MSqpNUrD3hPr/oXHqRyjNUUGMVqFZMqUk8z5tNpo9k9vi4QGEl6hESiRQI6Q8U6Dz9Br3+oKAKpNHL0cob/3Zzv3icoRBtkT8irBXD9jf4iUigSsg4GAYB4ZRQVSk0U6IwuvpPSy4MKagygqZEQSy0AQWcKNBlavSg2GBvOpvcTK4n83nlrOchhLYuq6/abfO/1XWjTIqtoSrlCefERafha/BxNNBpqTLs9b0/ZuPpdPL/hXKxDWU6m9w+3P96tzgeTE3QLaAoVxlNCUtzXSp4EXeMixQKolTEiSHBMLgcXo2CgW06G6nncYiQAf1izBIqY9Akl+mGCA7SCLMhhqoYDKGSE5ZnRQoGCMtLaXr9T1U4hQIODLTOle3TbWsMFFBODDybHkiWcyHjEJcm8q9wv0KyUtneRSGqT/BNhKzKIf4CjsIGPlBQpJRBD38//2W8uL5Dvv8lX/uSZhB+DgLfFsuvyjIa4XPUwWzY5m77sfVocZPfxw/+Yu7fjP2H4ZW/mAyDC38+tJ7a1cOhVXf04M7Gkrmu74rz/YyKdJ0/+xq+liAZoJqnVdOV9wzXYNKA8SdLfHaOjqhGZx0jjuAJFDIJlSgIbKC7gs55pyB7zXQIrvvo55qtTfGeagopsjLzmxmoWdsUnWvpRnW0xDuDlSsuJDWg8aoK3Ra2g13nKiuIFWgNHK0hzZ/qNA6kTQ5Ua1BmjzbcnfiWNSI0YUXptkhEhVtewKsNAs8sLTloIuNyNPzQrBA78e/YAnVQO4Nc84aOFiMhK84j1hlkGMncvGFmSxLGRXnU1n4P3C48Mm+ovXH6torBLtWxuTo/a3N8ZuuNvkM+IPzD7f3n8QNutXu5J2SZgRKMpvvXw7dRe6n0mhqWHK+RypCvon39YSOsheSamARIKd3dwl8Hkqv/2gIOTeyLCoXNw2qgExpcXPbqh5BjWW8M6F6/P0jgmYsYtOnttVGEJ39OJ9eLyQ2pcWR+Nw4uLsO/d738g0+kur1nt0kLyRRkIA1NiVEijkFVM6CZsFdrJBhZ56XkVG12rlJHg8LqcThIc8p17+VRcaosLqfaEQq3XEtcC/Fqr3mdcHnYeKuqOz9+aLV2zwFnc/L6a0XvvFeO7DLr2k2Ga5n9TLSQcQokoswei7PYT8vJlnhnR51yNWrD1iP7doivcJTzKrFXxsuTdXLRF3RTnfV+uo10P8X3Nnu1smumpXvg5wqvltgRnCTfm8e3yZ8ULQo4JG8a/dVpHk7CfjCNdIkP9kZ9+ByvkNDolqYa2pEZGCWY7mxPGYPCUMmAmESBTvKUd0fvNHhGjRLPbch/AesAIRwODgAA
B64

deploy_payload "$PREFLIGHT_REL" "$PREFLIGHT_SHA" <<'B64'
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
B64

test "$(sha256sum "$ROOT/src/29_nearing2022_da_ar/scripts/audit_partial_registered_results.py" | awk '{print $1}')" = "$AUDITOR_SHA"
test "$(sha256sum "$ROOT/src/29_nearing2022_da_ar/registry/evaluation_registry.csv" | awk '{print $1}')" = "$REGISTRY_SHA"
test "$(sha256sum "$ROOT/src/29_nearing2022_da_ar/reference/reproduction_acceptance.json" | awk '{print $1}')" = "$ACCEPTANCE_SHA"
test ! -e "$FINAL"
test "$(find "$(dirname "$FINAL")" -maxdepth 1 -name 'partial_numerical_audit_seq275_v1.preparing-*' -print -quit)" = ""
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
assert preflight["trigger"]["mailbox_sequence"] == 274
assert preflight["trigger"]["target"] == "N22-EVAL-TS-DA-L08-TE025-S0"
assert preflight["trigger"]["registered_complete_coordinates"] == 22
assert preflight["single_factor_change"]["predecessor_complete_coordinates"] == 21
assert preflight["single_factor_change"]["minimum_complete_coordinates"] == 22
assert preflight["single_factor_change"]["added_coordinates"] == [
    "N22-EVAL-TS-DA-L08-TE025-S0"
]
assert preflight["single_factor_change"]["excluded_nodes"] == ["ngu104"]
assert preflight["single_factor_change"]["other_scheduler_resources_changed"] is False
assert preflight["execution_contract"]["minimum_complete_coordinates"] == 22
assert preflight["scientific_boundary"]["numerical_auditor_changed"] is False
assert preflight["scientific_boundary"]["acceptance_thresholds_changed"] is False
wrapper = (root / sys.argv[2]).read_text(encoding="utf-8")
assert "#SBATCH --exclude=ngu104" in wrapper
assert wrapper.count("--mailbox-sequence 275 --minimum-complete 22") == 2
assert "#SBATCH --gres=gpu" not in wrapper and "#SBATCH --mem" not in wrapper
parts = wrapper.split("<<'PY'\n")
blocks = []
for part in parts[1:]:
    block, marker, _ = part.partition("\nPY\n")
    assert marker
    compile(block, "<seq275-slurm-heredoc>", "exec")
    blocks.append(block)
assert len(blocks) == 2
print(json.dumps({
    "deployment_hashes_verified": 3,
    "compiled_python_heredocs": len(blocks),
    "excluded_node": "ngu104",
    "minimum_complete_coordinates": 22,
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
