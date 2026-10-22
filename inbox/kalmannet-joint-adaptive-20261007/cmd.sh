#!/bin/bash
sequence=361
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
Q = {'sequence': 361, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e86f1c2865db500df8ff989381b12ad50fcf51c341bbebd796a9b018b8e5e7a9', 'ciphertext': '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'}}

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
