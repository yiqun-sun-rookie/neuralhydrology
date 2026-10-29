#!/usr/bin/env bash
set -e
python3 - <<'HPC_MAILBOX_BOOTSTRAP'

import base64, hashlib, io, json, os, pathlib, subprocess, sys, tarfile
s = json.loads(base64.b64decode('ewogICJjaGFubmVsIjogImthbG1hbm5ldC1wMDEtbG4tZmluYWwtaHBjIiwKICAiY29tbWFuZF9iYXNlNjQiOiAiSXlFdmRYTnlMMkpwYmk5bGJuWWdZbUZ6YUFvaklGSmxZV1F0YjI1c2VUb2djM1Z0YldGeWFYcGxJSFJvWlNCellYWmxaQ0JETGpFeElIQmhhWEpsWkNCaWIyOTBjM1J5WVhBZ1pISmhkM01nS0RJd01qWXRNVEF0TWprcExpQlhjbWwwWlhNZ2JtOTBhR2x1WnlCdmRYUnphV1JsSUhSb2FYTWdjbVZ4ZFdWemRDQmthWEpsWTNSdmNua3VDbk5sZENBdFpRcHpiM1Z5WTJVZ0wyUmhkR0V4TDJodmJXVXZjM1Z1ZVdseEwyMXBibWxqYjI1a1lUTXZaWFJqTDNCeWIyWnBiR1V1WkM5amIyNWtZUzV6YUFwamIyNWtZU0JoWTNScGRtRjBaU0JyYm1WMFgyTnNaV0Z1Q25CNWRHaHZiaUF0SUR3OEoxQlpKd3BwYlhCdmNuUWdZbUZ6WlRZMExDQm9ZWE5vYkdsaUxDQnBieXdnYW5OdmJncHBiWEJ2Y25RZ2JuVnRjSGtnWVhNZ2JuQUtSQ0E5SUNJdlpHRjBZVEV2YUc5dFpTOXpkVzU1YVhFdmEyRnNiV0Z1Ym1WMFgyTndkVjltY205NlpXNWZabWx1WVd4ZmMzUmhkR2x6ZEdsamMxOHlNREkyTVRBeE5GOHdNREV2Y0dGamEyRm5aUzltYVc1aGJGOXpkR0YwYVhOMGFXTnpJZ3BYUVU1VUlEMGdXeUowWlhOMFgxOXVaWFZ5WVd4ZmJXRnBibDl6WldWa05ESWlMQ0FpZEdWemRGOWZibVYxY21Gc1gyMWhhVzVmYzJWbFpEUXpJaXdnSW5SbGMzUmZYMjVsZFhKaGJGOXRZV2x1WDNObFpXUTBOQ0lzSUNKMFpYTjBYMTloY21Ob2FYWmxaRjlzWldGeWJtVmtYMjV2YVhObElsMEtiV1YwWVN3Z1lYSnlZWGx6SUQwZ2UzMHNJSHQ5Q21admNpQk1JR2x1SUNnNE1EQXNJRFF3TUN3Z01UWXdNQ2s2Q2lBZ0lDQndZWFJvSUQwZ1ppSjdSSDB2Y0dGcGNtVmtYMlJ5WVhkelgySnNiMk5yWDN0TWZTNXVjSG9pQ2lBZ0lDQjZJRDBnYm5BdWJHOWhaQ2h3WVhSb0xDQmhiR3h2ZDE5d2FXTnJiR1U5Um1Gc2MyVXBDaUFnSUNCcFpITWdQU0JiYzNSeUtIZ3BJR1p2Y2lCNElHbHVJSHBiSW0xbGRHaHZaRjlwWkhNaVhWMEtJQ0FnSUdRZ1BTQjZXeUp3WlhKZmJXVjBhRzlrWDJ4bFlXUmZibUZ6YUY5bFptWnBZMmxsYm1ONUlsMEtJQ0FnSUcxbGRHRmJjM1J5S0V3cFhTQTlJR1JwWTNRb2MyaGhNalUyUFdoaGMyaHNhV0l1YzJoaE1qVTJLRzl3Wlc0b2NHRjBhQ3dnSW5KaUlpa3VjbVZoWkNncEtTNW9aWGhrYVdkbGMzUW9LU3dnYTJWNWN6MXNhWE4wS0hvdVptbHNaWE1wTENCdFpYUm9iMlJmYVdSelBXbGtjeXdnYzJoaGNHVTliR2x6ZENoa0xuTm9ZWEJsS1N3S0lDQWdJQ0FnSUNBZ0lDQWdJQ0FnSUNBZ0lDQWdJQ0FnYzNSaGNuUnpYM05vWVRJMU5qMW9ZWE5vYkdsaUxuTm9ZVEkxTmloNld5SnpkR0Z5ZEhNaVhTNWhjM1I1Y0dVb0lqeHBPQ0lzSUdOdmNIazlSbUZzYzJVcExuUnZZbmwwWlhNb2IzSmtaWEk5SWtNaUtTa3VhR1Y0WkdsblpYTjBLQ2twQ2lBZ0lDQm1iM0lnYlNCcGJpQlhRVTVVT2dvZ0lDQWdJQ0FnSUdrZ1BTQnBaSE11YVc1a1pYZ29iU2tLSUNBZ0lDQWdJQ0J0WlhSaFczTjBjaWhNS1YxYmJTQXJJQ0pmWDI1aGJpSmRJRDBnYVc1MEtHNXdMbWx6Ym1GdUtHUmJPaXdnYVYwcExuTjFiU2dwS1FvZ0lDQWdJQ0FnSUdadmNpQnVZVzFsTENCc2J5d2dhR2tnYVc0Z0tDZ2lNVjh4TWlJc0lERXNJREV6S1N3Z0tDSXhNMTh5TkNJc0lERXpMQ0F5TlNrc0lDZ2lNVjh5TkNJc0lERXNJREkxS1NrNkNpQWdJQ0FnSUNBZ0lDQWdJR0Z5Y21GNWMxdG1JbUo3VEgxZlgzdHRmVjlmZTI1aGJXVjlJbDBnUFNCa1d6b3NJR2tzSUd4dk9taHBYUzV0WldGdUtHRjRhWE05TVNrS1luVm1JRDBnYVc4dVFubDBaWE5KVHlncE95QnVjQzV6WVhabGVsOWpiMjF3Y21WemMyVmtLR0oxWml3Z0tpcGhjbkpoZVhNcENuSmhkeUE5SUdKMVppNW5aWFIyWVd4MVpTZ3BDbkJ5YVc1MEtDSk5SVlJCSUNJZ0t5QnFjMjl1TG1SMWJYQnpLRzFsZEdFcEtRcHdjbWx1ZENnaVVFRlpURTlCUkY5VFNFRXlOVFlnSWlBcklHaGhjMmhzYVdJdWMyaGhNalUyS0hKaGR5a3VhR1Y0WkdsblpYTjBLQ2twQ25CeWFXNTBLQ0pRUVZsTVQwRkVYMEpCVTBVMk5DQWlJQ3NnWW1GelpUWTBMbUkyTkdWdVkyOWtaU2h5WVhjcExtUmxZMjlrWlNncEtRcFFXUW89IiwKICAiY29tbWFuZF9zaGEyNTYiOiAiMzEzNzJlMTcwMWY0OGEwZTA1NWFmZTdlYTRhYmZjNGI4ZTdmODdhMWNjMzQyNzEyYWRhNmJmMjllOTQwZTY4MyIsCiAgInBheWxvYWRfcGF0aCI6IG51bGwsCiAgInBheWxvYWRfc2hhMjU2IjogbnVsbCwKICAicHJvamVjdF9pZCI6ICJrYWxtYW5uZXQtcDAxLWxuLWZpbmFsIiwKICAicHJvdGVjdGVkX3JlbW90ZV9yb290cyI6IFsKICAgICIvZGF0YTEvaG9tZS9zdW55aXEvemhlbmppYW5nX2NvbXBsZXRlX2NvbXBhcmlzb25fMjAyNjEwMDZfMDAyIiwKICAgICIvZGF0YTEvaG9tZS9zdW55aXEvemhlbmppYW5nX2NvbXBsZXRlX2NvbXBhcmlzb25fZml4ZWQyMDBfMjAyNjEwMTlfMDAzIgogIF0sCiAgInByb3RvY29sIjogImNvbmZpZ3VyYWJsZS1ocGMtbWFpbGJveC12MSIsCiAgInJlbW90ZV9weXRob24iOiAicHl0aG9uMyIsCiAgInJlbW90ZV9yb290IjogIi9kYXRhMS9ob21lL3N1bnlpcS9ocGNfcHJvamVjdHMva2FsbWFubmV0LXAwMS1sbi1maW5hbCIsCiAgInJlcXVlc3RfaWQiOiAiZmV0Y2gtbWFpbi1kcmF3cy0wMDEiLAogICJzZXF1ZW5jZSI6IDEKfQo='))
root = pathlib.Path(s['remote_root']).resolve()
for old in s['protected_remote_roots']:
    p = pathlib.Path(old).resolve()
    if root == p or root in p.parents or p in root.parents:
        raise RuntimeError('Resolved work root overlaps a protected directory')
mailbox = pathlib.Path.cwd()
root.mkdir(parents=True, exist_ok=True)
area = root / '.hpc_mailbox' / (str(s['sequence']) + '_' + s['request_id'])
area.mkdir(parents=True, exist_ok=False)
payload_dir = area / 'payload'
payload_dir.mkdir()
if s['payload_path']:
    raw = (mailbox / s['payload_path']).read_bytes()
    if hashlib.sha256(raw).hexdigest() != s['payload_sha256']:
        raise RuntimeError('Payload checksum mismatch')
    with tarfile.open(fileobj=io.BytesIO(raw), mode='r:gz') as archive:
        seen = set()
        for m in archive:
            rel = pathlib.PurePosixPath(m.name)
            if (rel.is_absolute() or '..' in rel.parts or '\\' in m.name
                    or not (m.isfile() or m.isdir()) or str(rel) in seen):
                raise RuntimeError('Unsafe payload member')
            seen.add(str(rel))
            dest = payload_dir.joinpath(*rel.parts)
            if m.isdir():
                dest.mkdir(parents=True, exist_ok=True)
            else:
                dest.parent.mkdir(parents=True, exist_ok=True)
                with archive.extractfile(m) as src, dest.open('xb') as out:
                    import shutil
                    shutil.copyfileobj(src, out)
                dest.chmod(0o755 if m.mode & 0o111 else 0o644)
command = base64.b64decode(s['command_base64'])
if hashlib.sha256(command).hexdigest() != s['command_sha256']:
    raise RuntimeError('Command checksum mismatch')
task = area / 'task.sh'
task.write_bytes(command)
env = dict(os.environ, HPC_PROJECT_ID=s['project_id'], HPC_CHANNEL=s['channel'],
           HPC_REQUEST_ID=s['request_id'], HPC_REQUEST_SEQUENCE=str(s['sequence']),
           HPC_PROJECT_ROOT=str(root), HPC_REQUEST_DIR=str(area), HPC_PAYLOAD_DIR=str(payload_dir))
print(json.dumps({'hpc_mailbox_request': s['request_id'], 'project_id': s['project_id'],
                  'channel': s['channel'], 'sequence': s['sequence'], 'remote_root': str(root),
                  'payload_sha256': s['payload_sha256']}), flush=True)
returncode = subprocess.run(['bash', str(task)], cwd=str(root), env=env).returncode
print('', flush=True)
sys.exit(returncode)

HPC_MAILBOX_BOOTSTRAP
