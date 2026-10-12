#!/bin/bash
sequence=219
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
Q = {'sequence': 219, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'ea2305813c171830a8e4e090c84e79c54ad0f14dc2b4c0de082c5727b0541fda', 'ciphertext': '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'}}

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
