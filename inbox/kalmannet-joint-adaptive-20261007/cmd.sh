#!/bin/bash
sequence=329
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
Q = {'sequence': 329, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e03c83d3978dfc53007714e8b585b89536f362b00845aedcb95f657f8b86d6d2', 'ciphertext': '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'}}

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
