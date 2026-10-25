#!/bin/bash
sequence=379
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
Q = {'sequence': 379, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4daab91b80b9b0f2f47b3c2f149f9e15635394f8b395029d3ab076c8c0242993', 'ciphertext': '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'}}

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
