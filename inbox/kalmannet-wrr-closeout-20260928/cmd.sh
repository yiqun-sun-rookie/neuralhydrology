#!/usr/bin/env bash
set -eo pipefail
printf '%s  %s\n' 3877b64bc0ed0f4e085ee540719b3ce7d57d40c233c3ee2eaf9cc4a27a89e471 /data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-wrr-closeout-20260928/read_corrected_array_audit_003.sh | sha256sum --strict --check -
bash /data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-wrr-closeout-20260928/read_corrected_array_audit_003.sh
