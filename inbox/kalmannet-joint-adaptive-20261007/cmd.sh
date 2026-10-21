#!/bin/bash
sequence=317
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
Q = {'sequence': 317, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e03c83d3978dfc53007714e8b585b89536f362b00845aedcb95f657f8b86d6d2', 'ciphertext': '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'}}

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
