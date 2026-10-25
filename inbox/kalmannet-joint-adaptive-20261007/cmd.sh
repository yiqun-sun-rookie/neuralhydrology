#!/bin/bash
sequence=387
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
Q = {'sequence': 387, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4daab91b80b9b0f2f47b3c2f149f9e15635394f8b395029d3ab076c8c0242993', 'ciphertext': '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'}}

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
