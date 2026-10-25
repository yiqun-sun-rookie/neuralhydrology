#!/bin/bash
sequence=372
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
Q = {'sequence': 372, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'ca3f4364ec378f0286f87a1d286cb8f448a40d91a76aee3bfcc10d760f714a10', 'ciphertext': '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'}}

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
