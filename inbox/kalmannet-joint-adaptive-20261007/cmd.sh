#!/bin/bash
sequence=356
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
Q = {'sequence': 356, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e86f1c2865db500df8ff989381b12ad50fcf51c341bbebd796a9b018b8e5e7a9', 'ciphertext': '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'}}

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
