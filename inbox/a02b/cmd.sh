#!/bin/bash
# a02b seq=7 : why did `git add -A outbox` skip the 38MB bundle?
export LC_ALL=C
MBD=/data1/home/$USER/hpc_mailbox

echo "=== A FILE STILL THERE? ==="
timeout 20 ls -la "$MBD/outbox/"*.tar.gz 2>&1 | sed 's/^/  /'

cd "$MBD" || exit 1
echo "=== B IGNORE RULES ==="
echo "  --- check-ignore ---"
timeout 20 git check-ignore -v outbox/a02_lean_bundle.tar.gz 2>&1 | sed 's/^/    /' || echo "    (not ignored)"
echo "  --- .git/info/exclude ---"
timeout 15 cat .git/info/exclude 2>&1 | grep -v "^#" | grep -v "^$" | sed 's/^/    /' || echo "    (empty)"
echo "  --- .gitignore files present ---"
timeout 20 ls -la .gitignore outbox/.gitignore 2>&1 | sed 's/^/    /'
echo "  --- core.excludesfile ---"
timeout 15 git config --get core.excludesfile 2>&1 | sed 's/^/    /' || echo "    (unset)"

echo "=== C GIT STATUS OF OUTBOX ==="
timeout 40 git status --short outbox 2>&1 | head -10 | sed 's/^/  /'

echo "=== D FILTERS / LFS / SIZE LIMITS ==="
timeout 15 git config --get-regexp "^(lfs|http|pack)\." 2>&1 | sed 's/^/  /' | head -8
timeout 15 ls -la .gitattributes 2>&1 | sed 's/^/  /'

echo "=== E CAN WE ADD IT MANUALLY? (dry run) ==="
timeout 60 git add -n outbox/a02_lean_bundle.tar.gz 2>&1 | sed 's/^/  /' | head -3
