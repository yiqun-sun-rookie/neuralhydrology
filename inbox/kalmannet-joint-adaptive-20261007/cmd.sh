#!/bin/bash
sequence=360
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
Q = {'sequence': 360, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e86f1c2865db500df8ff989381b12ad50fcf51c341bbebd796a9b018b8e5e7a9', 'ciphertext': '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'}}

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
