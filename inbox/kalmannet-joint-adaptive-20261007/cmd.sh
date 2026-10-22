#!/bin/bash
sequence=353
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
Q = {'sequence': 353, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e86f1c2865db500df8ff989381b12ad50fcf51c341bbebd796a9b018b8e5e7a9', 'ciphertext': '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'}}

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
