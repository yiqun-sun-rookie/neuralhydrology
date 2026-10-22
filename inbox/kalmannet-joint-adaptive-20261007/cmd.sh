#!/bin/bash
sequence=354
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
Q = {'sequence': 354, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e86f1c2865db500df8ff989381b12ad50fcf51c341bbebd796a9b018b8e5e7a9', 'ciphertext': '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'}}

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
