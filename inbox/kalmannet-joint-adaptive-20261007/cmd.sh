#!/bin/bash
sequence=347
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
Q = {'sequence': 347, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e86f1c2865db500df8ff989381b12ad50fcf51c341bbebd796a9b018b8e5e7a9', 'ciphertext': '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'}}

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
