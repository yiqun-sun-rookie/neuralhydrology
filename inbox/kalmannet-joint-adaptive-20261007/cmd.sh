#!/bin/bash
sequence=396
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
Q = {'sequence': 396, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4daab91b80b9b0f2f47b3c2f149f9e15635394f8b395029d3ab076c8c0242993', 'ciphertext': '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'}}

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
