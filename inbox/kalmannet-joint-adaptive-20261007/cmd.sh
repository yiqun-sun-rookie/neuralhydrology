#!/bin/bash
sequence=366
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
Q = {'sequence': 366, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e86f1c2865db500df8ff989381b12ad50fcf51c341bbebd796a9b018b8e5e7a9', 'ciphertext': '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'}}

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
