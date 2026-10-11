#!/bin/bash
sequence=191
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
Q = {'sequence': 191, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '07fdf221f2166ac940aaa6cd932e18fbf0cd61bbe3a2623aa7eaf05641994bc5', 'ciphertext': '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'}}

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
