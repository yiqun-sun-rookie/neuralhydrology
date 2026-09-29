#!/bin/bash
# precip-selfrule-v05 seq=22: pin the fourth concurrency-probe reference record.
set -eo pipefail

TECH=/data1/home/sunyiq/precip_input_selfrule_time_v05_20260929_r03/technical_8/run01

date "+wallclock %F %T %z"
sha256sum "$TECH/fit/09512280.json"
