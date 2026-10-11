#!/bin/bash
sequence=202
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
Q = {'sequence': 202, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'cd339019cee443380ac85d60d36be8d7b1ec3a103f882ebb9565f20a36d8d99b', 'ciphertext': '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'}}

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
