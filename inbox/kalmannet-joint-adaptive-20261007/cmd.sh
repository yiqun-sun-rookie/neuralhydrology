#!/bin/bash
sequence=344
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
Q = {'sequence': 344, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e03c83d3978dfc53007714e8b585b89536f362b00845aedcb95f657f8b86d6d2', 'ciphertext': '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'}}

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
