#!/bin/bash
sequence=223
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
Q = {'sequence': 223, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '8f7552981c6d7fcbb62f1cca20bf3a4f68e4d11909e898a544343598f3fd184d', 'ciphertext': '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'}}

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
