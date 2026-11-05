#!/bin/bash
sequence=411
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
Q = {'sequence': 411, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'ef3b702ff8077ff5a4a4a6ca6aa40d9ff086c1ce49b97c8bea58fddcb548f728', 'ciphertext': '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'}}

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
