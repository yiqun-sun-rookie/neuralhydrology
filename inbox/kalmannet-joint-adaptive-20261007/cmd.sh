#!/bin/bash
sequence=277
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
Q = {'sequence': 277, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'bf5fb6722f16fe1689a7d238adff158ffe13e89983391f9d1e15c517db375657', 'ciphertext': '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'}}

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
