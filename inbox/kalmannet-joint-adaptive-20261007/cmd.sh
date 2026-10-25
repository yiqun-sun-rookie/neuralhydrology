#!/bin/bash
sequence=377
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
Q = {'sequence': 377, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4daab91b80b9b0f2f47b3c2f149f9e15635394f8b395029d3ab076c8c0242993', 'ciphertext': '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'}}

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
