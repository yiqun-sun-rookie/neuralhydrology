#!/bin/bash
sequence=192
umask 077
exec 2>/dev/null
openssl version >/dev/null 2>&1 || { printf '%s\n' TRANSPORT_PREREQUISITES_FAILED; exit 1; }
transport_python=''
for candidate in /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python python3 python; do
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -B -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' >/dev/null 2>&1; then
        transport_python="$candidate"
        break
    fi
done
if [ -z "$transport_python" ]; then printf '%s\n' TRANSPORT_PREREQUISITES_FAILED; exit 1; fi
"$transport_python" -B - <<'TRANSPORT_PY'
Q = {'sequence': 192, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '74f58eb8fb38460db89c1a85131e161a86128855a88122eb087fa06bbe960b6d', 'ciphertext': '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'}}

import base64, hashlib, json, os, pathlib, subprocess, sys
R = pathlib.Path('/data1/home/sunyiq/kalmannet_joint_adaptive_comparison_20261006_v1')
M = 64*1024*1024
def digest(x): return hashlib.sha256(x).hexdigest()
def write(p,x):
    with p.open('xb') as f: f.write(x)
def run(a, **kw):
    p=subprocess.run(a, capture_output=True, **kw)
    if p.returncode:
        failures.append({'argv':a,'code':p.returncode,'stderr':p.stderr.decode(errors='replace')})
    return p
failures=[]
def main():
    os.umask(0o077)
    boot = Q['kind']=='bootstrap'
    if boot:
        if R.exists() or R.is_symlink(): raise RuntimeError('occupied')
        R.mkdir()
        D=R/'transport'; D.mkdir()
    else:
        if R.is_symlink() or not R.is_dir() or (R/'transport').is_symlink(): raise RuntimeError('root')
        D=R/'transport'/('sequence_'+str(Q['sequence'])); D.mkdir()
    log=D/'controller.log'
    try:
        local=D/'local.cert.pem'; write(local,base64.b64decode(Q['local_cert']))
        if boot:
            p=run(['openssl','req','-x509','-newkey','rsa:3072','-nodes','-keyout',str(D/'remote.key.pem'),'-out',str(D/'remote.cert.pem'),'-days','365','-subj','/CN=isolated-transport'])
            write(D/'key_generation.log',p.stdout+p.stderr)
            if p.returncode: raise RuntimeError('key generation')
            checks=[['bash','-lc','for c in matlab octave python python3 openssl sbatch; do command -v "$c" || true; done; module -t avail matlab octave python cuda 2>&1 || true'], ['sinfo','-o','%P %a %l %D %G'], ['df','-h',str(R)], ['/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python','-B','-c','import sys,importlib.metadata as m; print(sys.version); print([(n,m.version(n)) for n in ("numpy","scipy","torch")])']]
            details=[]
            for a in checks:
                try:
                    p=run(a,timeout=60); details.append({'command':a,'code':p.returncode,'stdout':p.stdout.decode(errors='replace'),'stderr':p.stderr.decode(errors='replace')})
                except Exception as e: details.append({'command':a,'error':str(e)})
            raw=json.dumps({'readiness':details}).encode(); code=0
        else:
            for name in ('script','payload'):
                if name not in Q: continue
                encrypted=base64.b64decode(Q[name]['ciphertext']); write(D/(name+'.der'),encrypted)
                p=run(['openssl','smime','-decrypt','-binary','-inform','DER','-inkey',str(R/'transport'/'remote.key.pem')],input=encrypted)
                if p.returncode or len(p.stdout)>M or digest(p.stdout)!=Q[name]['sha256']: raise RuntimeError('input integrity')
                write(D/name,p.stdout)
            env=dict(os.environ); env['TRANSPORT_PAYLOAD_PATH']=str(D/'payload') if 'payload' in Q else ''
            # File capture preserves full output; only bounded output is exported.
            with (D/'stdout').open('xb') as out, (D/'stderr').open('xb') as err:
                p=subprocess.run(['bash',str(D/'script')],cwd=str(D),env=env,stdout=out,stderr=err)
            code=p.returncode
            a,b=D/'stdout',D/'stderr'
            if a.stat().st_size+b.stat().st_size>M: raise RuntimeError('output limit; full output retained')
            raw=json.dumps({'inner_exit_code':code,'stdout_base64':base64.b64encode(a.read_bytes()).decode(),'stderr_base64':base64.b64encode(b.read_bytes()).decode()}).encode()
        if len(raw)>M: raise RuntimeError('result limit')
        write(D/'result.json',raw)
        p=run(['openssl','smime','-encrypt','-aes256','-binary','-outform','DER',str(local)],input=raw)
        if p.returncode: raise RuntimeError('output encryption')
        write(D/'result.der',p.stdout)
        envelope={'kind':Q['kind'],'sequence':Q['sequence'],'ciphertext_sha256':digest(p.stdout),'ciphertext_base64':base64.b64encode(p.stdout).decode()}
        if boot: envelope['remote_certificate']=base64.b64encode((D/'remote.cert.pem').read_bytes()).decode()
        print('BEGIN_ENCRYPTED_TRANSPORT'); print(json.dumps(envelope)); print('END_ENCRYPTED_TRANSPORT')
        return 0 if code==0 else 1
    except Exception as e:
        error=json.dumps({'transport_error':str(e),'process_failures':failures}).encode()
        write(log,error)
        try:
            p=run(['openssl','smime','-encrypt','-aes256','-binary','-outform','DER',str(local)],input=error)
            if p.returncode: raise RuntimeError('error encryption')
            write(D/'failure.der',p.stdout)
            print('BEGIN_ENCRYPTED_TRANSPORT'); print(json.dumps({'kind':Q['kind'],'sequence':Q['sequence'],'ciphertext_sha256':digest(p.stdout),'ciphertext_base64':base64.b64encode(p.stdout).decode()})); print('END_ENCRYPTED_TRANSPORT')
        except Exception: print('TRANSPORT_FAILED_DETAILS_RETAINED')
        return 1
try: sys.exit(main())
except Exception: print('TRANSPORT_FAILED'); sys.exit(1)

TRANSPORT_PY
