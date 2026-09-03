#!/bin/bash
# Ship the artifact tarball as base64 text (precedent: outbox/id18-weight-merge/*.tar.gz.b64.txt).
set -o pipefail
SRC=~/hpc_mailbox/outbox/id23-param-probe/artifacts/parameter_axis_probe_v01_out_20260903.tar.gz
DST=~/hpc_mailbox/outbox/id23-param-probe/parameter_axis_probe_v01_out_20260903.tar.gz.b64.txt
sha256sum "$SRC"
base64 -w 76 "$SRC" > "$DST"
wc -c "$DST"
echo "b64 sha256: $(sha256sum "$DST" | cut -d' ' -f1)"
