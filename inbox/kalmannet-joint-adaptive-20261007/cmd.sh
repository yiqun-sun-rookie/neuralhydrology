#!/bin/bash
sequence=337
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
Q = {'sequence': 337, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e03c83d3978dfc53007714e8b585b89536f362b00845aedcb95f657f8b86d6d2', 'ciphertext': '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'}}

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
