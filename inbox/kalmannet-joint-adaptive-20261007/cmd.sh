#!/bin/bash
sequence=158
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
Q = {'sequence': 158, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '15960391f46e0f2f1906ca9cc7f4facee2a72b9d16809ca37e5b7f42174d5145', 'ciphertext': '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'}}

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
