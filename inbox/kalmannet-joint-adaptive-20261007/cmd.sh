#!/bin/bash
sequence=243
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
Q = {'sequence': 243, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'dbe1c6454e2e06b1359cea6f39e21f37a43b68f33335c8c70079a13529edcc05', 'ciphertext': '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'}}

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
