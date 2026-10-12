#!/bin/bash
sequence=232
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
Q = {'sequence': 232, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '992ca4568483b649c68d901dc6343a9f49b206786bea15866a9415c81e0e5ea3', 'ciphertext': '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'}}

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
