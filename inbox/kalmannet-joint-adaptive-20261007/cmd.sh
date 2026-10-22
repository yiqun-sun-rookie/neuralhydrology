#!/bin/bash
sequence=345
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
Q = {'sequence': 345, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e03c83d3978dfc53007714e8b585b89536f362b00845aedcb95f657f8b86d6d2', 'ciphertext': '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'}}

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
