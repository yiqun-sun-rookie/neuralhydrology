#!/bin/bash
sequence=378
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
Q = {'sequence': 378, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4daab91b80b9b0f2f47b3c2f149f9e15635394f8b395029d3ab076c8c0242993', 'ciphertext': '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'}}

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
