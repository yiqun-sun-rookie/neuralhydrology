#!/bin/bash
sequence=385
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
Q = {'sequence': 385, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4daab91b80b9b0f2f47b3c2f149f9e15635394f8b395029d3ab076c8c0242993', 'ciphertext': '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'}}

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
