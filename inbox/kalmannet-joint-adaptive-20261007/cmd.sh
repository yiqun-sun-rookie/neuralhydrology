#!/bin/bash
sequence=428
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
Q = {'sequence': 428, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4ddcbe331999b7705ac20312d59c72c9d9f6329db30e4baf3c62c83504753741', 'ciphertext': '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'}}

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
