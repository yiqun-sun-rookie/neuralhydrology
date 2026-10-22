#!/bin/bash
sequence=351
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
Q = {'sequence': 351, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e86f1c2865db500df8ff989381b12ad50fcf51c341bbebd796a9b018b8e5e7a9', 'ciphertext': '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'}}

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
