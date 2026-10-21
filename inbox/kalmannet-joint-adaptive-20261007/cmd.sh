#!/bin/bash
sequence=323
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
Q = {'sequence': 323, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e03c83d3978dfc53007714e8b585b89536f362b00845aedcb95f657f8b86d6d2', 'ciphertext': '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'}}

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
