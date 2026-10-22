#!/bin/bash
sequence=364
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
Q = {'sequence': 364, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e86f1c2865db500df8ff989381b12ad50fcf51c341bbebd796a9b018b8e5e7a9', 'ciphertext': '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'}}

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
