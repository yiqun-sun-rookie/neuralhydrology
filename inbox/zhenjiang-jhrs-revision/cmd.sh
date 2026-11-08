#!/usr/bin/env bash
set -e
python3 - <<'HPC_MAILBOX_BOOTSTRAP'

import base64, hashlib, io, json, os, pathlib, subprocess, sys, tarfile
s = json.loads(base64.b64decode('ewogICJjaGFubmVsIjogInpoZW5qaWFuZy1qaHJzLXJldmlzaW9uIiwKICAiY29tbWFuZF9iYXNlNjQiOiAiSXlFdmRYTnlMMkpwYmk5bGJuWWdZbUZ6YUFvaklGSmxZV1F0YjI1c2VUb2djR1Z5TFdWc1pXMWxiblFnYzNSaGRHVnpJRzltSUdGeWNtRjVJREkxT0RJeU1Td2daM0p2ZFhCbFpDQmllU0J6WldWa0lISmhibWRsTGdwelpYUWdMWFVLVTB3OUwzVnpjaTlzYjJOaGJDOW5iRzlpYkdVdmMyOW1kSE12YzJ4MWNtMHZNVGt1TURVdU5DNHhMMkpwYmdwa1lYUmxDbVZqYUc4Z0lpTWpJSE54ZFdWMVpTSTdJQ1JUVEM5emNYVmxkV1VnTFdvZ01qVTRNakl4SUMxb0lDMXZJQ0lsYVNBbFZDSWdNajRtTVNCOElHaGxZV1FnTFRnS1pXTm9ieUFpSXlNZ2MyRmpZM1FnWld4bGJXVnVkSE1nWW5rZ2MzUmhkR1VnWVc1a0lITmxaV1FnWW14dlkyc2lDaVJUVEM5ellXTmpkQ0F0YWlBeU5UZ3lNakVnTFc0Z0xWQWdMUzFtYjNKdFlYUTlTbTlpU1VRc1UzUmhkR1VnTWo0dlpHVjJMMjUxYkd3Z2ZDQmhkMnNnTFVZbmZDY2dKeVF4SUg0Z0wxNHlOVGd5TWpGZkx5QjdJSE53YkdsMEtDUXhMQ0JoTENBaVh5SXBPeUJwSUQwZ1lWc3lYVHNnWjNOMVlpZ3ZYRnQ4WEYwdkxDQWlJaXdnYVNrN0lHSnNheUE5SUNocEt6QWdQajBnTnpZNEtTQS9JQ0l4TWpjaUlEb2dLR2tyTUNBK1BTQTJOeklwSUQ4Z0lqRXdPU0lnT2lBaU9UY2lPeUJ6VzJKc2F5SWdJaVF5WFNzcklIMGdSVTVFSUhzZ1ptOXlJQ2hySUdsdUlITXBJSEJ5YVc1MElHc3NJSE5iYTEwZ2ZTY2dmQ0J6YjNKMENtVmphRzhnSWlNaklHZ3hJSFJoYzJ0eklHTnZiWEJzWlhSbE9pQWtLR3h6SUNJa1NGQkRYMUJTVDBwRlExUmZVazlQVkNJdmFERmZkakV2YURGZmRHRnphM012S2k5amIyMXdiR1YwYVc5dVgyMWhibWxtWlhOMExtcHpiMjRnTWo0dlpHVjJMMjUxYkd3Z2ZDQjNZeUF0YkNraUNnPT0iLAogICJjb21tYW5kX3NoYTI1NiI6ICIzMDQ3Y2MwOGM4OTdhZWRmNmMxMWM4ZmNhNDg0NjkyNzQ0OThiOWU0Zjk1ZDZkMWY2ZWNlMGM5Y2U3NGU2YzdjIiwKICAicGF5bG9hZF9wYXRoIjogbnVsbCwKICAicGF5bG9hZF9zaGEyNTYiOiBudWxsLAogICJwcm9qZWN0X2lkIjogInpoZW5qaWFuZy1qaHJzLXJldmlzaW9uIiwKICAicHJvdGVjdGVkX3JlbW90ZV9yb290cyI6IFsKICAgICIvZGF0YTEvaG9tZS9zdW55aXEvemhlbmppYW5nX2NvbXBsZXRlX2NvbXBhcmlzb25fMjAyNjEwMDZfMDAyIiwKICAgICIvZGF0YTEvaG9tZS9zdW55aXEvemhlbmppYW5nX2NvbXBsZXRlX2NvbXBhcmlzb25fZml4ZWQyMDBfMjAyNjEwMTlfMDAzIgogIF0sCiAgInByb3RvY29sIjogImNvbmZpZ3VyYWJsZS1ocGMtbWFpbGJveC12MSIsCiAgInJlbW90ZV9weXRob24iOiAicHl0aG9uMyIsCiAgInJlbW90ZV9yb290IjogIi9kYXRhMS9ob21lL3N1bnlpcS9ocGNfcHJvamVjdHMvemhlbmppYW5nLWpocnMtcmV2aXNpb24iLAogICJyZXF1ZXN0X2lkIjogImNoZWNrLWFycmF5LTI1ODIyMS0wMDEiLAogICJzZXF1ZW5jZSI6IDE0Cn0K'))
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
