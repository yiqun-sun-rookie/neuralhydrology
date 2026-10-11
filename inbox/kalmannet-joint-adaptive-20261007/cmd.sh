#!/bin/bash
sequence=169
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
Q = {'sequence': 169, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '0765ccedb1456f89f56dabf8a0ded52b55b7a13c2785eb5ae582f2918af2a90b', 'ciphertext': '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'}}

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
