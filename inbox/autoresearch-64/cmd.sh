#!/bin/bash
set -euo pipefail

MAILBOX=/data1/home/sunyiq/hpc_mailbox
PYTHON=/data1/home/sunyiq/autoresearch64/.venv/bin/python
CORRECTED=/tmp/autoresearch64-submit-seq64.sh

test ! -e "$CORRECTED"
"$PYTHON" - "$MAILBOX" "$CORRECTED" <<'PY_FIX'
import hashlib
import os
import subprocess
import sys
from pathlib import Path

mailbox = Path(sys.argv[1])
output_path = Path(sys.argv[2])
source = subprocess.run(
    [
        "git",
        "-C",
        str(mailbox),
        "show",
        "98ecf5e9:inbox/autoresearch-64/cmd.sh",
    ],
    check=True,
    capture_output=True,
    text=True,
).stdout
if source.count("seq62") != 7:
    raise SystemExit("unexpected sequence-62 template count")
if source.count("sequence 62") != 1:
    raise SystemExit("unexpected snapshot-label template count")
bad = r'\n+echo "=== VERIFY IMMUTABLE RECOMMENDATION RECEIPT ==="'
good = r'\necho "=== VERIFY IMMUTABLE RECOMMENDATION RECEIPT ==="'
if source.count(bad) != 1:
    raise SystemExit("unexpected literal-plus defect count")

corrected = source.replace("seq62", "seq64")
corrected = corrected.replace("sequence 62", "sequence 64")
corrected = corrected.replace(bad, good)
if "+echo" in corrected:
    raise SystemExit("literal-plus defect remains after correction")

descriptor = os.open(output_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o444)
with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
    stream.write(corrected)
    stream.flush()
    os.fsync(stream.fileno())
print(f"corrected_submit_sha256={hashlib.sha256(corrected.encode('utf-8')).hexdigest()}")
PY_FIX

bash -n "$CORRECTED"
bash "$CORRECTED"
