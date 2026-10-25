#!/bin/bash
sequence=375
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
Q = {'sequence': 375, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'ca3f4364ec378f0286f87a1d286cb8f448a40d91a76aee3bfcc10d760f714a10', 'ciphertext': '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'}}

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
