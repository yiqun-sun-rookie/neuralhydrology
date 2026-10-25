#!/bin/bash
sequence=371
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
Q = {'sequence': 371, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'ca3f4364ec378f0286f87a1d286cb8f448a40d91a76aee3bfcc10d760f714a10', 'ciphertext': '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'}}

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
