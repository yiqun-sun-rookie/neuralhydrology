#!/bin/bash
# ID29 seq=212: rerun the frozen sequence-207 read-only full health audit with Git 1.8-compatible cwd handling.
set -eo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR/../.."
git show 49c4a2ae550f97bad1a69ba6daf0482f52642dcf:inbox/id29-nearing2022-da/cmd.sh | bash
