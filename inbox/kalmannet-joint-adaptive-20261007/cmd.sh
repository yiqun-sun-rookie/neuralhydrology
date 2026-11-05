#!/bin/bash
sequence=418
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
Q = {'sequence': 418, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e38bb8fba06b13aa9b6c15dc19d97280624d1ed3b0eeeefedbaea491934fb829', 'ciphertext': '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'}}

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
