#!/bin/bash
sequence=264
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
Q = {'sequence': 264, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '6894cfcfd28d52e3c1c79c52f88f3aeba154b55729a9041a29aa38493accaccb', 'ciphertext': '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'}}

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
