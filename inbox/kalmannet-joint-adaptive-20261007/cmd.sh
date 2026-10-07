#!/bin/bash
sequence=22
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
Q = {'sequence': 22, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e1454e14f87865f53bf08e5b1a1f305cf5a2cd6cfdf393500c949e2888cf6b1b', 'ciphertext': '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'}}

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
