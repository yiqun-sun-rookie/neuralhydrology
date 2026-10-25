#!/bin/bash
sequence=373
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
Q = {'sequence': 373, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'ca3f4364ec378f0286f87a1d286cb8f448a40d91a76aee3bfcc10d760f714a10', 'ciphertext': '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'}}

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
