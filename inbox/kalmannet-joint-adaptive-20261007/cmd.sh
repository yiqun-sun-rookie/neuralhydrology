#!/bin/bash
sequence=106
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
Q = {'sequence': 106, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e1b5ff5eaed8531b2cef039edad5e4259c0c2d6b726fe70b16ac5760bf347d98', 'ciphertext': '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'}}

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
