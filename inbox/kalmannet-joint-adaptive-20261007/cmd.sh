#!/bin/bash
sequence=358
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
Q = {'sequence': 358, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e86f1c2865db500df8ff989381b12ad50fcf51c341bbebd796a9b018b8e5e7a9', 'ciphertext': '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'}}

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
