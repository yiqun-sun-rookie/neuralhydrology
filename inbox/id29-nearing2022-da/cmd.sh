#!/bin/bash
# ID29 seq=211: rerun the frozen sequence-207 read-only full health audit against current live state.
set -eo pipefail

MAILBOX_ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
git -C "$MAILBOX_ROOT" show \
  49c4a2ae550f97bad1a69ba6daf0482f52642dcf:inbox/id29-nearing2022-da/cmd.sh | bash
