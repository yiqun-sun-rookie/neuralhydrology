#!/bin/bash
sequence=124
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
Q = {'sequence': 124, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '0765ccedb1456f89f56dabf8a0ded52b55b7a13c2785eb5ae582f2918af2a90b', 'ciphertext': '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'}}

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
