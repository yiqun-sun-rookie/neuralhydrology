#!/bin/bash
sequence=348
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
Q = {'sequence': 348, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e86f1c2865db500df8ff989381b12ad50fcf51c341bbebd796a9b018b8e5e7a9', 'ciphertext': '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'}}

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
