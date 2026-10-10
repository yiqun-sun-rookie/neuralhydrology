#!/bin/bash
sequence=112
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
Q = {'sequence': 112, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4386ee0c09239e1f08eebc2dd0363ff59b17a674e8dea019a5abdf82636765c4', 'ciphertext': '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'}}

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
