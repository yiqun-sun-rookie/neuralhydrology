#!/bin/bash
sequence=18
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
Q = {'sequence': 18, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e159a9327f0975a04a6d3a9ec461ebd22d27f36df798ac8976d4d852fa0e5e46', 'ciphertext': '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'}}

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
