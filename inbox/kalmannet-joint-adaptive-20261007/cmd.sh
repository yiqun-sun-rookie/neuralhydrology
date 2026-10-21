#!/bin/bash
sequence=319
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
Q = {'sequence': 319, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e03c83d3978dfc53007714e8b585b89536f362b00845aedcb95f657f8b86d6d2', 'ciphertext': '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'}}

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
