#!/bin/bash
sequence=62
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
Q = {'sequence': 62, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '6f52ec681874ec3ab3caf5606fe667fbc17635d695c7bb107d12601caf8fb1f4', 'ciphertext': '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'}}

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
