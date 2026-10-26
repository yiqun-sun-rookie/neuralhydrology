#!/bin/bash
sequence=400
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
Q = {'sequence': 400, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4daab91b80b9b0f2f47b3c2f149f9e15635394f8b395029d3ab076c8c0242993', 'ciphertext': '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'}}

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
