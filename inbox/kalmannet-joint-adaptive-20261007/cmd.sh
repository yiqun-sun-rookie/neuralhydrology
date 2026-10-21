#!/bin/bash
sequence=326
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
Q = {'sequence': 326, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e03c83d3978dfc53007714e8b585b89536f362b00845aedcb95f657f8b86d6d2', 'ciphertext': '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'}}

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
