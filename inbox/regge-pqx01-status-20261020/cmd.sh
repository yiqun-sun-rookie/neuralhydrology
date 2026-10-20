#!/bin/bash
set -eu
printf 'probe_id=regge-vpn-only-20261020-1655\n'
printf 'read_only=true\n'
date -u '+utc=%Y-%m-%dT%H:%M:%SZ'
hostname
id -un
printf 'No jobs, files, services, or receiver settings were changed by this probe.\n'
