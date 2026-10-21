#!/bin/bash
sequence=320
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
Q = {'sequence': 320, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e03c83d3978dfc53007714e8b585b89536f362b00845aedcb95f657f8b86d6d2', 'ciphertext': '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'}}

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
