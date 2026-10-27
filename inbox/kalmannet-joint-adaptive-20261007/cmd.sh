#!/bin/bash
sequence=409
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
Q = {'sequence': 409, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4daab91b80b9b0f2f47b3c2f149f9e15635394f8b395029d3ab076c8c0242993', 'ciphertext': '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'}}

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
