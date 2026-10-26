#!/bin/bash
sequence=405
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
Q = {'sequence': 405, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4daab91b80b9b0f2f47b3c2f149f9e15635394f8b395029d3ab076c8c0242993', 'ciphertext': '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'}}

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
