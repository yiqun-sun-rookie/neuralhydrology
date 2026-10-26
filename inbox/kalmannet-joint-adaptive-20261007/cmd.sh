#!/bin/bash
sequence=391
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
Q = {'sequence': 391, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4daab91b80b9b0f2f47b3c2f149f9e15635394f8b395029d3ab076c8c0242993', 'ciphertext': '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'}}

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
