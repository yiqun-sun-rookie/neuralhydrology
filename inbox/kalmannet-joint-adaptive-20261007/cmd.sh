#!/bin/bash
sequence=74
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
Q = {'sequence': 74, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '558d420a8551f3a5c5345f7e3d6ff6af40b280ea5d3a36107386fefb02f41f35', 'ciphertext': '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'}}

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
