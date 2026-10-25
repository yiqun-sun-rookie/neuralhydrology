#!/bin/bash
sequence=370
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
Q = {'sequence': 370, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'ca3f4364ec378f0286f87a1d286cb8f448a40d91a76aee3bfcc10d760f714a10', 'ciphertext': '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'}}

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
