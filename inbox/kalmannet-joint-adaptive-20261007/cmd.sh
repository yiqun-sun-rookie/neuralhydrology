#!/bin/bash
sequence=398
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
Q = {'sequence': 398, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4daab91b80b9b0f2f47b3c2f149f9e15635394f8b395029d3ab076c8c0242993', 'ciphertext': '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'}}

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
