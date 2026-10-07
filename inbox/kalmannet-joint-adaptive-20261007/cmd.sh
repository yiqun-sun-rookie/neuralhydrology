#!/bin/bash
sequence=32
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
Q = {'sequence': 32, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'd8ccfacff3561ecb04653943729c6965ebba81a4173ab7fc1d6fa6a052563522', 'ciphertext': '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'}}

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
