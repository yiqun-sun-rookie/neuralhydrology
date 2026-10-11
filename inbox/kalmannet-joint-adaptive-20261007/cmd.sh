#!/bin/bash
sequence=204
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
Q = {'sequence': 204, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'ea14e68732ad406396c9478cd0e80fee0e341ddd3557a7b9491eb9330ae546fe', 'ciphertext': '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'}}

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
