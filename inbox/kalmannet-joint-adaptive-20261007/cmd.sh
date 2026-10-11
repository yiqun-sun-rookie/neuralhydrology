#!/bin/bash
sequence=209
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
Q = {'sequence': 209, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '7d77c4df39a9c1fbe7d7dceb0bfd98bd1d61f83edd2e2e2d588f0c2274e33724', 'ciphertext': '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'}}

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
