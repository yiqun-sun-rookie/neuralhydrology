#!/usr/bin/env bash
set -eo pipefail
printf '%s  %s\n' \
  8d44fd0a9e25e2c8d3d0d15a09da5c69096579a003d136a90eb4e4289ab7155b /data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-wrr-closeout-20260928/submission_guard_003.sh \
  acddf691984ef5f1b2116667a4b2de1a4ed9b94b6c6f4c68d5eb23e622d80da2 /data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-wrr-closeout-20260928/submit_corrected_array_audit_003.sh \
  3877b64bc0ed0f4e085ee540719b3ce7d57d40c233c3ee2eaf9cc4a27a89e471 /data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-wrr-closeout-20260928/read_corrected_array_audit_003.sh | sha256sum --strict --check -
bash /data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-wrr-closeout-20260928/submission_guard_003.sh 85463b8eec09b581c2a0e8cd14c14f2a35ccfd951a1db5a31701424aee50d848
