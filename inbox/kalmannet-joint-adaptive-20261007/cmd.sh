#!/bin/bash
sequence=322
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
Q = {'sequence': 322, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e03c83d3978dfc53007714e8b585b89536f362b00845aedcb95f657f8b86d6d2', 'ciphertext': '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'}}

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
