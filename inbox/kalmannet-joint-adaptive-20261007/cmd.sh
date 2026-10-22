#!/bin/bash
sequence=357
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
Q = {'sequence': 357, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e86f1c2865db500df8ff989381b12ad50fcf51c341bbebd796a9b018b8e5e7a9', 'ciphertext': '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'}}

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
