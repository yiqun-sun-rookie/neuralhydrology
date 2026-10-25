#!/bin/bash
sequence=383
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
Q = {'sequence': 383, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4daab91b80b9b0f2f47b3c2f149f9e15635394f8b395029d3ab076c8c0242993', 'ciphertext': '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'}}

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
