#!/bin/bash
sequence=148
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
Q = {'sequence': 148, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '0765ccedb1456f89f56dabf8a0ded52b55b7a13c2785eb5ae582f2918af2a90b', 'ciphertext': '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'}}

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
