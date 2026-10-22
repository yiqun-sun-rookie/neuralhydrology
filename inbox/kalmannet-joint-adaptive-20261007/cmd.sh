#!/bin/bash
sequence=352
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
Q = {'sequence': 352, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e86f1c2865db500df8ff989381b12ad50fcf51c341bbebd796a9b018b8e5e7a9', 'ciphertext': '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'}}

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
