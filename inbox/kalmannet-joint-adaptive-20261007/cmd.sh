#!/bin/bash
sequence=338
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
Q = {'sequence': 338, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e03c83d3978dfc53007714e8b585b89536f362b00845aedcb95f657f8b86d6d2', 'ciphertext': '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'}}

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
