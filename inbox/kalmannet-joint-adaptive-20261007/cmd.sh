#!/bin/bash
sequence=350
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
Q = {'sequence': 350, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e86f1c2865db500df8ff989381b12ad50fcf51c341bbebd796a9b018b8e5e7a9', 'ciphertext': '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'}}

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
