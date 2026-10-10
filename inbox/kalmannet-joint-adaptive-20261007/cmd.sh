#!/bin/bash
sequence=131
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
Q = {'sequence': 131, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '193cabdb5c85e18bc91d4a9b7bf7b45b9ca105be8dca548b07e2ef820c2a2c79', 'ciphertext': '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'}}

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
