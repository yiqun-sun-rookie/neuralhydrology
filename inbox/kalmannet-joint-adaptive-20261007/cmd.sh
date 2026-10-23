#!/bin/bash
sequence=365
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
Q = {'sequence': 365, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e86f1c2865db500df8ff989381b12ad50fcf51c341bbebd796a9b018b8e5e7a9', 'ciphertext': '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'}}

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
