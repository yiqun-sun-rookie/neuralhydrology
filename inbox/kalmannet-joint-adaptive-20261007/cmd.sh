#!/bin/bash
sequence=404
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
Q = {'sequence': 404, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4daab91b80b9b0f2f47b3c2f149f9e15635394f8b395029d3ab076c8c0242993', 'ciphertext': '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'}}

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
