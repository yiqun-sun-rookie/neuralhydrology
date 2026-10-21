#!/bin/bash
sequence=339
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
Q = {'sequence': 339, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e03c83d3978dfc53007714e8b585b89536f362b00845aedcb95f657f8b86d6d2', 'ciphertext': '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'}}

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
