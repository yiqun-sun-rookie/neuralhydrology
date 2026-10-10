#!/bin/bash
sequence=153
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
Q = {'sequence': 153, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '0765ccedb1456f89f56dabf8a0ded52b55b7a13c2785eb5ae582f2918af2a90b', 'ciphertext': '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'}}

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
