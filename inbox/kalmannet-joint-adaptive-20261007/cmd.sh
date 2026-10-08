#!/bin/bash
sequence=61
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
Q = {'sequence': 61, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'c593b1312e91b326c8110993a81362f101664278531f4a4b0ae1ee6e32364702', 'ciphertext': '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'}}

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
