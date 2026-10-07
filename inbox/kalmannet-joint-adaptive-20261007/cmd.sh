#!/bin/bash
sequence=31
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
Q = {'sequence': 31, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e535fd2caa8d28015bcce93894e199a06cab2aa2924dcb98f5ff0f5810b9faf7', 'ciphertext': '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'}}

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
