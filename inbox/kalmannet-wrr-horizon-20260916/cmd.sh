#!/bin/bash
set -eo pipefail
printf 'ISOLATED_DEPLOYMENT_AND_SINGLE_SUBMISSION\n'
date -Is
cd /data1/home/sunyiq/hpc_mailbox/payload/kalmannet-wrr-horizon-20260916/deployment-001
printf '%s\n' 'c36f271d233d9d6ae6e455f41b2c8fecf15839884adb6a07367c291178060ebc  study.tar.gz' '91e5eafe82debc081f036e5de51b5de9e4cf58c6193a98a6c4cb81f4b6dff995  deploy.py' '58f602a0b049950ed7e60000159bbc1ba39f71f3f2ec6e7562c342dce96fc9b8  PACKAGE_MANIFEST.json' | sha256sum -c -
/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -I -B deploy.py "$PWD"
