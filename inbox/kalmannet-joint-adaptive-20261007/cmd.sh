#!/bin/bash
sequence=390
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
Q = {'sequence': 390, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4daab91b80b9b0f2f47b3c2f149f9e15635394f8b395029d3ab076c8c0242993', 'ciphertext': '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'}}

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
