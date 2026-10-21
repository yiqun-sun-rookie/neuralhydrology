#!/bin/bash
sequence=334
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
Q = {'sequence': 334, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e03c83d3978dfc53007714e8b585b89536f362b00845aedcb95f657f8b86d6d2', 'ciphertext': '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'}}

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
