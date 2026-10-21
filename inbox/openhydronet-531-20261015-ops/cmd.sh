#!/bin/bash
# DRILL ONLY: remove the VERSION note from my own shared install so the repair path can be exercised once
SH=/data1/home/sunyiq/openhydronet_shared
chmod u+w "$SH" && rm -f "$SH/VERSION" && chmod a-w "$SH" && echo "DRILL: removed VERSION"; ls "$SH"
exit 0
