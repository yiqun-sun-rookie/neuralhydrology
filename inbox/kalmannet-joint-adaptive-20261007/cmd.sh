#!/bin/bash
sequence=408
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
Q = {'sequence': 408, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4daab91b80b9b0f2f47b3c2f149f9e15635394f8b395029d3ab076c8c0242993', 'ciphertext': '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'}}

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
