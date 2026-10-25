#!/bin/bash
sequence=374
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
Q = {'sequence': 374, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'ca3f4364ec378f0286f87a1d286cb8f448a40d91a76aee3bfcc10d760f714a10', 'ciphertext': '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'}}

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
