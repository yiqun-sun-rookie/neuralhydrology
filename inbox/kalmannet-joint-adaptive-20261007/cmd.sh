#!/bin/bash
sequence=363
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
Q = {'sequence': 363, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e86f1c2865db500df8ff989381b12ad50fcf51c341bbebd796a9b018b8e5e7a9', 'ciphertext': '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'}}

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
