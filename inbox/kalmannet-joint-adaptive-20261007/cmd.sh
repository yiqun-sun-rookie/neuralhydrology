#!/bin/bash
sequence=369
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
Q = {'sequence': 369, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'ca3f4364ec378f0286f87a1d286cb8f448a40d91a76aee3bfcc10d760f714a10', 'ciphertext': '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'}}

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
