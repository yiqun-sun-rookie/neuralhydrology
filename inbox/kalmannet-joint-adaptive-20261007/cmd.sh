#!/bin/bash
sequence=362
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
Q = {'sequence': 362, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e86f1c2865db500df8ff989381b12ad50fcf51c341bbebd796a9b018b8e5e7a9', 'ciphertext': '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'}}

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
