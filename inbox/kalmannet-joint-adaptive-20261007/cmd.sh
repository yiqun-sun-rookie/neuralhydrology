#!/bin/bash
sequence=399
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
Q = {'sequence': 399, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'cb83b58df5141b200a22f7218edc9ab35fbabd53f9260f42f5d5d4aabc451502', 'ciphertext': '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'}}

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
