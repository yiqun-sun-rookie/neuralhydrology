#!/bin/bash
sequence=215
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
Q = {'sequence': 215, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '86e2cb919c88d691b36e6e8677cff226a832f56a9a56d1a95813933692803c7e', 'ciphertext': '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'}}

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
