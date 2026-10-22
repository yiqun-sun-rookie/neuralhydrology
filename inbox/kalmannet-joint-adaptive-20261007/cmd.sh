#!/bin/bash
sequence=355
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
Q = {'sequence': 355, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e86f1c2865db500df8ff989381b12ad50fcf51c341bbebd796a9b018b8e5e7a9', 'ciphertext': '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'}}

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
